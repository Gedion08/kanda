// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IBasketVault} from "../interfaces/IBasketVault.sol";
import {IKandaToken} from "../interfaces/IKandaToken.sol";
import {IParticipantRegistry} from "../interfaces/IParticipantRegistry.sol";
import {Roles} from "../governance/Roles.sol";

/// @title BasketVault
/// @notice Holds the KND basket reserves and runs in-kind create and redeem. The only path that mints KND, and it
///         mints only against basket assets the vault has actually received. Spec: L1 section 3.3.
/// @dev No price oracle is read here (AGENTS.md). Rounding: pulls round up, payouts and mints round down, fees
///      round up, which keeps INV-1 (review section 2). UUPS proxy behind the timelock; ERC-7201 storage.
contract BasketVault is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient,
    IBasketVault
{
    using SafeERC20 for IERC20;

    uint256 private constant UNIT = 1e18;
    uint256 private constant BPS = 10_000;
    uint16 private constant MAX_FEE_BPS = 100;
    uint32 private constant GENESIS_VERSION = 1;

    /// @custom:storage-location erc7201:kanda.storage.BasketVault
    struct VaultStorage {
        address knd;
        address registry;
        uint32 basketVersion;
        bool createPaused;
        uint16 feeBps;
        address feeRecipient;
        uint256 supplyCap;
        Leg[] legs;
    }

    // keccak256(abi.encode(uint256(keccak256("kanda.storage.BasketVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULT_STORAGE_LOCATION =
        0x11d4b46d44b307138832abd4461c9952c34cd4d86312ebb49ec76ae5daedef00;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the proxy with the genesis basket (version 1), supply cap and fee from the network config.
    ///         Grants only DEFAULT_ADMIN_ROLE; WireRoles grants the rest (L1 section 7).
    /// @param admin Initial DEFAULT_ADMIN_ROLE holder (the deployer, who renounces after wiring).
    /// @param knd KandaToken proxy.
    /// @param registry ParticipantRegistry proxy.
    /// @param genesisLegs Basket legs: non-empty, non-zero distinct assets, non-zero quantities.
    /// @param supplyCap Initial supply cap in KND base units.
    /// @param feeBps Initial fee, at most 100 bps.
    /// @param feeRecipient Fee recipient (the treasury Safe); must be non-zero.
    function initialize(
        address admin,
        address knd,
        address registry,
        Leg[] calldata genesisLegs,
        uint256 supplyCap,
        uint16 feeBps,
        address feeRecipient
    ) external initializer {
        if (admin == address(0) || knd == address(0) || registry == address(0)) revert ZeroAddress();
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        VaultStorage storage $ = _getVaultStorage();
        $.knd = knd;
        $.registry = registry;
        _setGenesisBasket($, genesisLegs);
        _setSupplyCap($, supplyCap);
        _setFee($, feeBps, feeRecipient);
    }

    // =============================================================
    // Create and redeem
    // =============================================================

    /// @inheritdoc IBasketVault
    function createInKind(uint256 kndAmount, uint256 minKndOut, address to)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 kndOut)
    {
        VaultStorage storage $ = _getVaultStorage();

        // 1. Checks.
        if ($.createPaused) revert CreationPaused();
        if (kndAmount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        if (IKandaToken($.knd).isBlocked(to)) revert IKandaToken.AccountBlocked(to);
        if (!IParticipantRegistry($.registry).isParticipant(msg.sender)) {
            revert IParticipantRegistry.NotActive(msg.sender);
        }

        // 2-3. Pull each leg rounded up; the scarcest leg, by amount actually received, decides the gross mint.
        uint256 legCount = $.legs.length;
        uint256[] memory amountsIn = new uint256[](legCount);
        uint256 kndGross = kndAmount;
        for (uint256 i; i < legCount; ++i) {
            Leg memory leg = $.legs[i];
            IERC20 asset = IERC20(leg.asset);
            uint256 required = Math.mulDiv(kndAmount, leg.qtyPerUnit, UNIT, Math.Rounding.Ceil);

            // forge-lint: disable-next-line(calls-loop) -- every create moves every leg (L1 3.3); legs are the fixed, vetted reserve tokens
            uint256 balanceBefore = asset.balanceOf(address(this));
            asset.safeTransferFrom(msg.sender, address(this), required);
            // forge-lint: disable-next-line(calls-loop) -- balance delta measures fee-on-transfer receipts (L1 3.3 step 2)
            uint256 received = asset.balanceOf(address(this)) - balanceBefore;

            amountsIn[i] = received;
            uint256 backs = Math.mulDiv(received, UNIT, leg.qtyPerUnit, Math.Rounding.Floor);
            if (backs < kndGross) kndGross = backs;
        }

        // 4. Supply cap, then the participant's daily limit.
        uint256 newSupply = IERC20($.knd).totalSupply() + kndGross;
        if (newSupply > $.supplyCap) revert SupplyCapExceeded(newSupply, $.supplyCap);
        IParticipantRegistry($.registry).consumeCreate(msg.sender, kndGross);

        // 5. Fee rounds up; net to `to`, fee to the recipient.
        uint256 fee = Math.mulDiv(kndGross, $.feeBps, BPS, Math.Rounding.Ceil);
        kndOut = kndGross - fee;
        if (kndOut < minKndOut) revert MintBelowMin(kndOut, minKndOut);

        // forge-lint: disable-next-line(reentrancy-events) -- nonReentrant; calls are to KND, the registry and the legs
        emit Created(msg.sender, to, kndGross, fee, amountsIn);
        IKandaToken($.knd).mint(to, kndOut);
        if (fee > 0) IKandaToken($.knd).mint($.feeRecipient, fee);
    }

    /// @inheritdoc IBasketVault
    function redeemInKind(uint256 kndAmount, uint256[] calldata minAmountsOut, address to)
        external
        nonReentrant
        whenNotPaused
        returns (uint256[] memory amountsOut)
    {
        VaultStorage storage $ = _getVaultStorage();

        // 1. Checks. A creation pause does not apply to redeem.
        if (kndAmount == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        uint256 legCount = $.legs.length;
        if (minAmountsOut.length != legCount) revert LengthMismatch(legCount, minAmountsOut.length);
        if (!IParticipantRegistry($.registry).isParticipant(msg.sender)) {
            revert IParticipantRegistry.NotActive(msg.sender);
        }
        IParticipantRegistry($.registry).consumeRedeem(msg.sender, kndAmount);

        // 3 (computed first). Payouts round down on the net; check every minimum before moving anything.
        uint256 fee = Math.mulDiv(kndAmount, $.feeBps, BPS, Math.Rounding.Ceil);
        uint256 net = kndAmount - fee;
        amountsOut = _payouts($, net);
        for (uint256 i; i < legCount; ++i) {
            // forge-lint: disable-next-line(require-revert-in-loop) -- per-leg slippage bound is the caller's protection (SlippageOut)
            if (amountsOut[i] < minAmountsOut[i]) revert SlippageOut(i, amountsOut[i], minAmountsOut[i]);
        }

        // forge-lint: disable-next-line(reentrancy-events) -- nonReentrant; calls are to KND, the registry and the legs
        emit Redeemed(msg.sender, to, kndAmount, fee, amountsOut);

        // 2. Pull the KND; the fee stays in circulation, the net is burned.
        IERC20 kndToken = IERC20($.knd);
        kndToken.safeTransferFrom(msg.sender, address(this), kndAmount);
        if (fee > 0) kndToken.safeTransfer($.feeRecipient, fee);
        IKandaToken($.knd).burn(net);

        // 3. Pay the basket. Zero amounts are skipped: some tokens revert on zero transfers.
        for (uint256 i; i < legCount; ++i) {
            if (amountsOut[i] > 0) IERC20($.legs[i].asset).safeTransfer(to, amountsOut[i]);
        }
    }

    // =============================================================
    // Views
    // =============================================================

    /// @inheritdoc IBasketVault
    function previewCreate(uint256 kndAmount) external view returns (uint256[] memory amountsIn, uint256 kndOutNet) {
        VaultStorage storage $ = _getVaultStorage();
        uint256 legCount = $.legs.length;
        amountsIn = new uint256[](legCount);
        for (uint256 i; i < legCount; ++i) {
            amountsIn[i] = Math.mulDiv(kndAmount, $.legs[i].qtyPerUnit, UNIT, Math.Rounding.Ceil);
        }
        kndOutNet = kndAmount - Math.mulDiv(kndAmount, $.feeBps, BPS, Math.Rounding.Ceil);
    }

    /// @inheritdoc IBasketVault
    function previewRedeem(uint256 kndAmount) external view returns (uint256[] memory amountsOut) {
        VaultStorage storage $ = _getVaultStorage();
        return _payouts($, kndAmount - Math.mulDiv(kndAmount, $.feeBps, BPS, Math.Rounding.Ceil));
    }

    /// @inheritdoc IBasketVault
    function legs() external view returns (uint32 version, Leg[] memory) {
        VaultStorage storage $ = _getVaultStorage();
        return ($.basketVersion, $.legs);
    }

    /// @inheritdoc IBasketVault
    function coverage() external view returns (uint256[] memory ratiosBps) {
        VaultStorage storage $ = _getVaultStorage();
        uint256 legCount = $.legs.length;
        uint256 supply = IERC20($.knd).totalSupply();
        ratiosBps = new uint256[](legCount);
        for (uint256 i; i < legCount; ++i) {
            if (supply == 0) {
                ratiosBps[i] = type(uint256).max;
                continue;
            }
            Leg storage leg = $.legs[i];
            uint256 required = Math.mulDiv(supply, leg.qtyPerUnit, UNIT, Math.Rounding.Ceil);
            // forge-lint: disable-next-line(calls-loop) -- view over the fixed legs; coverage per leg is the spec'd output
            ratiosBps[i] = Math.mulDiv(IERC20(leg.asset).balanceOf(address(this)), BPS, required);
        }
    }

    /// @inheritdoc IBasketVault
    function createPaused() external view returns (bool) {
        return _getVaultStorage().createPaused;
    }

    // =============================================================
    // Administration
    // =============================================================

    /// @inheritdoc IBasketVault
    function setSupplyCap(uint256 cap) external onlyRole(Roles.LIMITS_ADMIN_ROLE) {
        _setSupplyCap(_getVaultStorage(), cap);
    }

    /// @inheritdoc IBasketVault
    function setFee(uint16 feeBps, address recipient) external onlyRole(Roles.LIMITS_ADMIN_ROLE) {
        _setFee(_getVaultStorage(), feeBps, recipient);
    }

    /// @inheritdoc IBasketVault
    function pause() external onlyRole(Roles.PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IBasketVault
    function unpause() external onlyRole(Roles.UNPAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IBasketVault
    function pauseCreate() external onlyRole(Roles.PAUSER_ROLE) {
        _getVaultStorage().createPaused = true;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call in this function
        emit CreatePaused(_msgSender());
    }

    /// @inheritdoc IBasketVault
    function unpauseCreate() external onlyRole(Roles.UNPAUSER_ROLE) {
        _getVaultStorage().createPaused = false;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call in this function
        emit CreateUnpaused(_msgSender());
    }

    // =============================================================
    // Internal
    // =============================================================

    function _payouts(VaultStorage storage $, uint256 net) private view returns (uint256[] memory amounts) {
        uint256 legCount = $.legs.length;
        amounts = new uint256[](legCount);
        for (uint256 i; i < legCount; ++i) {
            amounts[i] = Math.mulDiv(net, $.legs[i].qtyPerUnit, UNIT, Math.Rounding.Floor);
        }
    }

    function _setGenesisBasket(VaultStorage storage $, Leg[] calldata genesisLegs) private {
        uint256 legCount = genesisLegs.length;
        if (legCount == 0) revert InvalidBasket();
        for (uint256 i; i < legCount; ++i) {
            Leg calldata leg = genesisLegs[i];
            // forge-lint: disable-next-line(require-revert-in-loop) -- genesis basket validation, initializer only
            if (leg.asset == address(0) || leg.qtyPerUnit == 0) revert InvalidBasket();
            for (uint256 j; j < i; ++j) {
                // forge-lint: disable-next-line(require-revert-in-loop) -- duplicate-asset check, initializer only
                if (genesisLegs[j].asset == leg.asset) revert InvalidBasket();
            }
            $.legs.push(leg);
        }
        $.basketVersion = GENESIS_VERSION;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: initializer path, no external call
        emit BasketVersionSet(GENESIS_VERSION, genesisLegs);
    }

    function _setSupplyCap(VaultStorage storage $, uint256 cap) private {
        $.supplyCap = cap;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call in this function
        emit SupplyCapSet(cap);
    }

    function _setFee(VaultStorage storage $, uint16 feeBps, address recipient) private {
        if (recipient == address(0)) revert ZeroAddress();
        if (feeBps > MAX_FEE_BPS) revert FeeTooHigh(feeBps);
        $.feeBps = feeBps;
        $.feeRecipient = recipient;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call in this function
        emit FeeSet(feeBps, recipient);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER_ROLE) {}

    function _getVaultStorage() private pure returns (VaultStorage storage $) {
        assembly {
            $.slot := VAULT_STORAGE_LOCATION
        }
    }
}
