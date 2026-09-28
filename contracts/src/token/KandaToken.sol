// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IKandaToken} from "../interfaces/IKandaToken.sol";
import {Roles} from "../governance/Roles.sol";

/// @title KandaToken (KND)
/// @notice Reserve-backed basket token: 1 KND = 0.70 USD + G oz gold, held in BasketVault. Only MINTER_ROLE
///         (BasketVault) mints, and only against basket assets the vault has received. Spec: L1 section 3.1.
/// @dev UUPS proxy behind the 48-hour timelock (ADD section 4). Own state lives in ERC-7201 namespaced storage.
///      No seize function: blocked balances stay frozen until the Compliance Safe unblocks them.
contract KandaToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardTransient,
    IKandaToken
{
    using SafeERC20 for IERC20;

    string private constant NAME = "Kanda";
    string private constant SYMBOL = "KND";

    bytes32 private constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 private constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 private constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");

    /// @custom:storage-location erc7201:kanda.storage.KandaToken
    struct KandaTokenStorage {
        mapping(address account => bool) blocked;
        mapping(address authorizer => mapping(bytes32 nonce => bool)) authorizationStates;
    }

    // keccak256(abi.encode(uint256(keccak256("kanda.storage.KandaToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant KANDA_TOKEN_STORAGE_LOCATION =
        0xedfafc115e36e8673ee7cb02d06638cbb83fab9dd026fdeb53f1d6c738202d00;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the proxy. Grants only DEFAULT_ADMIN_ROLE; WireRoles grants the rest (L1 section 7).
    /// @param admin Initial DEFAULT_ADMIN_ROLE holder (the deployer, who renounces after wiring).
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAddress();
        __ERC20_init(NAME, SYMBOL);
        __ERC20Permit_init(NAME);
        __Pausable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // =============================================================
    // Mint and burn (MINTER_ROLE)
    // =============================================================

    /// @inheritdoc IKandaToken
    function mint(address to, uint256 amount) external onlyRole(Roles.MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    /// @inheritdoc IKandaToken
    function burn(uint256 amount) external onlyRole(Roles.MINTER_ROLE) whenNotPaused {
        _burn(_msgSender(), amount);
    }

    /// @inheritdoc IKandaToken
    function burnFrom(address from, uint256 amount) external onlyRole(Roles.MINTER_ROLE) whenNotPaused {
        _spendAllowance(from, _msgSender(), amount);
        _burn(from, amount);
    }

    // =============================================================
    // Blocklist (COMPLIANCE_ROLE)
    // =============================================================

    /// @inheritdoc IKandaToken
    function blockAccount(address account) external onlyRole(Roles.COMPLIANCE_ROLE) {
        // Blocking address(0) would stop every mint and burn.
        if (account == address(0)) revert ZeroAddress();
        _getKandaTokenStorage().blocked[account] = true;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call precedes this emit
        emit Blocked(account);
    }

    /// @inheritdoc IKandaToken
    function unblockAccount(address account) external onlyRole(Roles.COMPLIANCE_ROLE) {
        _getKandaTokenStorage().blocked[account] = false;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call precedes this emit
        emit Unblocked(account);
    }

    /// @inheritdoc IKandaToken
    function isBlocked(address account) external view returns (bool) {
        return _getKandaTokenStorage().blocked[account];
    }

    // =============================================================
    // Rescue (DEFAULT_ADMIN_ROLE)
    // =============================================================

    /// @inheritdoc IKandaToken
    function rescueERC20(address token, address to, uint256 amount) external nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(this)) revert CannotRescueKnd();
        if (to == address(0)) revert ZeroAddress();
        // forge-lint: disable-next-line(reentrancy-events) -- emitted before the transfer, guarded by nonReentrant
        emit Rescued(token, to, amount);
        IERC20(token).safeTransfer(to, amount);
    }

    // =============================================================
    // Pause (PAUSER_ROLE / UNPAUSER_ROLE)
    // =============================================================

    /// @inheritdoc IKandaToken
    function pause() external onlyRole(Roles.PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IKandaToken
    function unpause() external onlyRole(Roles.UNPAUSER_ROLE) {
        _unpause();
    }

    // =============================================================
    // ERC-20 overrides
    // =============================================================

    /// @notice Transfer `value` from `from` to `to` using the caller's allowance.
    /// @dev Reverts AccountBlocked if the spender is blocked; from and to are checked in _update.
    /// @param from Payer.
    /// @param to Payee.
    /// @param value Amount in base units.
    /// @return True on success.
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _requireNotBlocked(_msgSender());
        return super.transferFrom(from, to, value);
    }

    // =============================================================
    // EIP-3009
    // =============================================================

    /// @inheritdoc IKandaToken
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _useAuthorization(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, v, r, s
        );
        _transfer(from, to, value);
    }

    /// @inheritdoc IKandaToken
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (to != _msgSender()) revert CallerMustBePayee(_msgSender(), to);
        _useAuthorization(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce, v, r, s);
        _transfer(from, to, value);
    }

    /// @inheritdoc IKandaToken
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {
        _requireUnusedAuthorization(authorizer, nonce);
        _requireValidSignature(
            authorizer, keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)), v, r, s
        );
        _getKandaTokenStorage().authorizationStates[authorizer][nonce] = true;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call precedes this emit
        emit AuthorizationCanceled(authorizer, nonce);
    }

    /// @inheritdoc IKandaToken
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _getKandaTokenStorage().authorizationStates[authorizer][nonce];
    }

    // =============================================================
    // Internal
    // =============================================================

    /// @dev Every balance change passes here: mint, burn, transfer, transferFrom and EIP-3009.
    ///      Reverts while paused, or if either side is blocked (a mint to a blocked address also reverts).
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        _requireNotBlocked(from);
        _requireNotBlocked(to);
        super._update(from, to, value);
    }

    function _useAuthorization(
        bytes32 typehash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        // EIP-3009 validity window; validator drift of a few seconds cannot move value.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp <= validAfter) revert AuthorizationNotYetValid();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= validBefore) revert AuthorizationExpired();
        _requireUnusedAuthorization(from, nonce);
        _requireValidSignature(
            from, keccak256(abi.encode(typehash, from, to, value, validAfter, validBefore, nonce)), v, r, s
        );
        _getKandaTokenStorage().authorizationStates[from][nonce] = true;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call precedes this emit
        emit AuthorizationUsed(from, nonce);
    }

    function _requireUnusedAuthorization(address authorizer, bytes32 nonce) private view {
        if (_getKandaTokenStorage().authorizationStates[authorizer][nonce]) {
            revert AuthorizationUsedOrCanceled(authorizer, nonce);
        }
    }

    /// @dev The EIP-712 domain includes block.chainid, so a signature from another chain never verifies.
    function _requireValidSignature(address signer, bytes32 structHash, uint8 v, bytes32 r, bytes32 s) private view {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(_hashTypedDataV4(structHash), v, r, s);
        if (err != ECDSA.RecoverError.NoError || recovered != signer) revert InvalidSignature();
    }

    function _requireNotBlocked(address account) private view {
        if (_getKandaTokenStorage().blocked[account]) revert AccountBlocked(account);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER_ROLE) {}

    function _getKandaTokenStorage() private pure returns (KandaTokenStorage storage $) {
        assembly {
            $.slot := KANDA_TOKEN_STORAGE_LOCATION
        }
    }
}
