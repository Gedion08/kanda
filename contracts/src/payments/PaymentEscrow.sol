// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IPaymentEscrow} from "../interfaces/IPaymentEscrow.sol";
import {IKandaToken} from "../interfaces/IKandaToken.sol";
import {IParticipantRegistry} from "../interfaces/IParticipantRegistry.sol";
import {Roles} from "../governance/Roles.sol";

/// @title PaymentEscrow
/// @notice Holds KND per payment intent between two registered partners. The sender locks; the sender or the
///         releaser pays the receiver; the receiver can reject; anyone refunds after expiry; either party can
///         dispute before expiry and the arbiter splits. Spec: L1 section 3.4.
/// @dev Transitions: None -> Locked (lock); Locked -> Released (release), Refunded (reject, refund), Disputed
///      (dispute); Disputed -> Resolved (resolve). Released, Refunded and Resolved are terminal (INV-5). Every call
///      checks status first, then the caller, then time. Exit paths don't re-check the registry (review C-12).
///      UUPS proxy behind the timelock; ERC-7201 storage.
contract PaymentEscrow is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient,
    IPaymentEscrow
{
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:kanda.storage.PaymentEscrow
    struct EscrowStorage {
        address knd;
        address registry;
        uint64 minExpiry;
        uint64 maxExpiry;
        mapping(bytes32 intentId => Intent) intents;
    }

    // keccak256(abi.encode(uint256(keccak256("kanda.storage.PaymentEscrow")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ESCROW_STORAGE_LOCATION =
        0x10dcaa107d1502d16c47f95420a6309951629b2d5eb5a3fb1c4a19ac81535d00;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the proxy with the expiry window from the network config (config escrow.minExpiry and
    ///         escrow.maxExpiry). Grants only DEFAULT_ADMIN_ROLE; WireRoles grants the rest (L1 section 7).
    /// @param admin Initial DEFAULT_ADMIN_ROLE holder (the deployer, who renounces after wiring).
    /// @param knd KandaToken proxy.
    /// @param registry ParticipantRegistry proxy.
    /// @param minExpiry Shortest allowed lock, in seconds.
    /// @param maxExpiry Longest allowed lock, in seconds.
    function initialize(address admin, address knd, address registry, uint64 minExpiry, uint64 maxExpiry)
        external
        initializer
    {
        if (admin == address(0) || knd == address(0) || registry == address(0)) revert ZeroAddress();
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        EscrowStorage storage $ = _getEscrowStorage();
        $.knd = knd;
        $.registry = registry;
        _setExpiryBounds($, minExpiry, maxExpiry);
    }

    // =============================================================
    // Intents
    // =============================================================

    /// @inheritdoc IPaymentEscrow
    function lock(bytes32 intentId, address receiver, uint128 amount, uint64 expiry, bytes32 metadataHash)
        external
        nonReentrant
        whenNotPaused
    {
        EscrowStorage storage $ = _getEscrowStorage();
        address sender = _msgSender();

        if ($.intents[intentId].status != Status.None) revert IntentExists(intentId);
        if (amount == 0) revert ZeroAmount();
        if (receiver == sender) revert SameParty(sender);
        // forge-lint: disable-next-line(block-timestamp) -- expiry window in minutes to hours; seconds of drift are harmless
        if (expiry < block.timestamp + $.minExpiry || expiry > block.timestamp + $.maxExpiry) revert BadExpiry(expiry);
        IParticipantRegistry registry = IParticipantRegistry($.registry);
        if (!registry.isPartner(sender)) revert IParticipantRegistry.NotActive(sender);
        if (!registry.isPartner(receiver)) revert IParticipantRegistry.NotActive(receiver);
        // A blocked sender fails in the transfer below; a blocked receiver must fail here, before KND is locked.
        if (IKandaToken($.knd).isBlocked(receiver)) revert IKandaToken.AccountBlocked(receiver);

        $.intents[intentId] = Intent({
            sender: sender,
            receiver: receiver,
            amount: amount,
            expiry: expiry,
            status: Status.Locked,
            metadataHash: metadataHash
        });
        // forge-lint: disable-next-line(reentrancy-events) -- only view calls precede this; the transfer follows it (CEI, nonReentrant)
        emit Locked(intentId, sender, receiver, amount, expiry, metadataHash);
        IERC20($.knd).safeTransferFrom(sender, address(this), amount);
    }

    /// @inheritdoc IPaymentEscrow
    function release(bytes32 intentId) external nonReentrant whenNotPaused {
        EscrowStorage storage $ = _getEscrowStorage();
        Intent storage intent = _requireStatus($, intentId, Status.Locked);
        address caller = _msgSender();
        if (caller != intent.sender && !hasRole(Roles.RELEASER_ROLE, caller)) revert Unauthorized(caller);

        intent.status = Status.Released;
        // forge-lint: disable-next-line(reentrancy-events) -- only view calls precede this; the transfer follows it (CEI, nonReentrant)
        emit Released(intentId, caller);
        IERC20($.knd).safeTransfer(intent.receiver, intent.amount);
    }

    /// @inheritdoc IPaymentEscrow
    function reject(bytes32 intentId) external nonReentrant whenNotPaused {
        EscrowStorage storage $ = _getEscrowStorage();
        Intent storage intent = _requireStatus($, intentId, Status.Locked);
        address caller = _msgSender();
        if (caller != intent.receiver) revert Unauthorized(caller);

        intent.status = Status.Refunded;
        // forge-lint: disable-next-line(reentrancy-events) -- only view calls precede this; the transfer follows it (CEI, nonReentrant)
        emit Refunded(intentId, caller);
        IERC20($.knd).safeTransfer(intent.sender, intent.amount);
    }

    /// @inheritdoc IPaymentEscrow
    function refund(bytes32 intentId) external nonReentrant whenNotPaused {
        EscrowStorage storage $ = _getEscrowStorage();
        Intent storage intent = _requireStatus($, intentId, Status.Locked);
        // Refund opens at expiry, the same second dispute closes: no gap, no overlap.
        // forge-lint: disable-next-line(block-timestamp) -- expiry is minutes to hours away; seconds of drift are harmless
        if (block.timestamp < intent.expiry) revert NotExpired(intentId);

        intent.status = Status.Refunded;
        // forge-lint: disable-next-line(reentrancy-events) -- only view calls precede this; the transfer follows it (CEI, nonReentrant)
        emit Refunded(intentId, _msgSender());
        IERC20($.knd).safeTransfer(intent.sender, intent.amount);
    }

    /// @inheritdoc IPaymentEscrow
    function dispute(bytes32 intentId) external whenNotPaused {
        Intent storage intent = _requireStatus(_getEscrowStorage(), intentId, Status.Locked);
        address caller = _msgSender();
        if (caller != intent.sender && caller != intent.receiver) revert Unauthorized(caller);
        // forge-lint: disable-next-line(block-timestamp) -- expiry is minutes to hours away; seconds of drift are harmless
        if (block.timestamp >= intent.expiry) revert BadExpiry(intent.expiry);

        intent.status = Status.Disputed;
        // forge-lint: disable-next-line(reentrancy-events) -- only view calls precede this; the transfer follows it (CEI, nonReentrant)
        emit Disputed(intentId, caller);
    }

    /// @inheritdoc IPaymentEscrow
    function resolve(bytes32 intentId, uint128 toReceiver)
        external
        nonReentrant
        whenNotPaused
        onlyRole(Roles.ARBITER_ROLE)
    {
        EscrowStorage storage $ = _getEscrowStorage();
        Intent storage intent = _requireStatus($, intentId, Status.Disputed);
        uint128 amount = intent.amount;
        if (toReceiver > amount) revert InvalidSplit(toReceiver, amount);
        uint128 toSender = amount - toReceiver;

        intent.status = Status.Resolved;
        // forge-lint: disable-next-line(reentrancy-events) -- only view calls precede this; the transfer follows it (CEI, nonReentrant)
        emit Resolved(intentId, toReceiver, toSender);
        IERC20 knd = IERC20($.knd);
        if (toReceiver > 0) knd.safeTransfer(intent.receiver, toReceiver);
        if (toSender > 0) knd.safeTransfer(intent.sender, toSender);
    }

    /// @inheritdoc IPaymentEscrow
    function intents(bytes32 intentId) external view returns (Intent memory) {
        return _getEscrowStorage().intents[intentId];
    }

    // =============================================================
    // Administration
    // =============================================================

    /// @inheritdoc IPaymentEscrow
    /// @dev Not gated by the pause, so the timelock can adjust the window during an incident (SCP-13).
    function setExpiryBounds(uint64 minExpiry, uint64 maxExpiry) external onlyRole(Roles.LIMITS_ADMIN_ROLE) {
        _setExpiryBounds(_getEscrowStorage(), minExpiry, maxExpiry);
    }

    /// @inheritdoc IPaymentEscrow
    function pause() external onlyRole(Roles.PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IPaymentEscrow
    function unpause() external onlyRole(Roles.UNPAUSER_ROLE) {
        _unpause();
    }

    // =============================================================
    // Internal
    // =============================================================

    function _requireStatus(EscrowStorage storage $, bytes32 intentId, Status expected)
        private
        view
        returns (Intent storage intent)
    {
        intent = $.intents[intentId];
        if (intent.status != expected) revert BadStatus(intentId, intent.status);
    }

    function _setExpiryBounds(EscrowStorage storage $, uint64 minExpiry, uint64 maxExpiry) private {
        if (minExpiry == 0 || minExpiry > maxExpiry) revert InvalidExpiryBounds(minExpiry, maxExpiry);
        $.minExpiry = minExpiry;
        $.maxExpiry = maxExpiry;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call in this function
        emit ExpiryBoundsSet(minExpiry, maxExpiry);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER_ROLE) {}

    function _getEscrowStorage() private pure returns (EscrowStorage storage $) {
        assembly {
            $.slot := ESCROW_STORAGE_LOCATION
        }
    }
}
