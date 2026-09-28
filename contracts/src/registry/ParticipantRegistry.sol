// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IParticipantRegistry} from "../interfaces/IParticipantRegistry.sol";
import {Roles} from "../governance/Roles.sol";

/// @title ParticipantRegistry
/// @notice Who may use the primary market (participants) and the escrow (partners), with tiered daily create and
///         redeem limits that reset at UTC midnight. Spec: L1 section 3.2.
/// @dev UUPS proxy behind the timelock (ADD section 4); state in ERC-7201 namespaced storage. Deployed before the
///      vault, so consumers are authorized by LIMITS_CONSUMER_ROLE, granted by WireRoles (SCP-02).
contract ParticipantRegistry is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IParticipantRegistry {
    /// @custom:storage-location erc7201:kanda.storage.ParticipantRegistry
    struct RegistryStorage {
        mapping(address account => Account) accounts;
        mapping(uint8 tier => TierLimits) tiers;
        mapping(uint8 tier => bool) tierExists;
    }

    // keccak256(abi.encode(uint256(keccak256("kanda.storage.ParticipantRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REGISTRY_STORAGE_LOCATION =
        0x532998f640c1c55ad4fcd78d62f693bc8582b3df1029f60449125e88fb695e00;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the proxy. Grants only DEFAULT_ADMIN_ROLE; WireRoles grants the rest (L1 section 7).
    /// @param admin Initial DEFAULT_ADMIN_ROLE holder (the deployer, who renounces after wiring).
    function initialize(address admin) external initializer {
        if (admin == address(0)) revert ZeroAddress();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // =============================================================
    // Administration
    // =============================================================

    /// @inheritdoc IParticipantRegistry
    function setAccount(address account, Kind kind, uint8 tier, bool active)
        external
        onlyRole(Roles.PARTICIPANT_MANAGER_ROLE)
    {
        if (account == address(0)) revert ZeroAddress();
        RegistryStorage storage $ = _getRegistryStorage();
        if (!$.tierExists[tier]) revert UnknownTier(tier);

        // Only the registration changes; day and today's counters stay, so re-setting cannot lift a daily limit.
        Account storage acct = $.accounts[account];
        acct.kind = kind;
        acct.tier = tier;
        acct.active = active;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call in this function
        emit AccountSet(account, kind, tier, active);
    }

    /// @inheritdoc IParticipantRegistry
    function setTier(uint8 tier, TierLimits calldata limits) external onlyRole(Roles.LIMITS_ADMIN_ROLE) {
        RegistryStorage storage $ = _getRegistryStorage();
        $.tiers[tier] = limits;
        $.tierExists[tier] = true;
        // forge-lint: disable-next-line(reentrancy-events) -- false positive: no external call in this function
        emit TierSet(tier, limits.dailyCreate, limits.dailyRedeem);
    }

    // =============================================================
    // Consumption (LIMITS_CONSUMER_ROLE)
    // =============================================================

    /// @inheritdoc IParticipantRegistry
    function consumeCreate(address account, uint256 amount) external onlyRole(Roles.LIMITS_CONSUMER_ROLE) {
        _consume(account, amount, true);
    }

    /// @inheritdoc IParticipantRegistry
    function consumeRedeem(address account, uint256 amount) external onlyRole(Roles.LIMITS_CONSUMER_ROLE) {
        _consume(account, amount, false);
    }

    // =============================================================
    // Views
    // =============================================================

    /// @inheritdoc IParticipantRegistry
    function isParticipant(address account) external view returns (bool) {
        return _isParticipant(_getRegistryStorage().accounts[account]);
    }

    /// @inheritdoc IParticipantRegistry
    function isPartner(address account) external view returns (bool) {
        Account storage acct = _getRegistryStorage().accounts[account];
        return acct.active && (acct.kind == Kind.Partner || acct.kind == Kind.Both);
    }

    /// @inheritdoc IParticipantRegistry
    function remaining(address account) external view returns (uint256 create, uint256 redeem) {
        RegistryStorage storage $ = _getRegistryStorage();
        Account storage acct = $.accounts[account];
        if (!_isParticipant(acct)) return (0, 0);

        // Counters from an earlier day are stale and count as zero (lazy reset).
        // forge-lint: disable-next-line(block-timestamp) -- UTC day index (L1 3.2); seconds of drift only move the rollover by seconds
        bool sameDay = acct.day == _today();
        TierLimits storage limits = $.tiers[acct.tier];
        create = _left(limits.dailyCreate, sameDay ? acct.createdToday : 0);
        redeem = _left(limits.dailyRedeem, sameDay ? acct.redeemedToday : 0);
    }

    // =============================================================
    // Internal
    // =============================================================

    function _consume(address account, uint256 amount, bool isCreate) private {
        RegistryStorage storage $ = _getRegistryStorage();
        Account storage acct = $.accounts[account];
        if (!_isParticipant(acct)) revert NotActive(account);

        uint32 today = _today();
        // forge-lint: disable-next-line(block-timestamp) -- UTC day index (L1 3.2); seconds of drift only move the rollover by seconds
        if (acct.day != today) {
            acct.day = today;
            acct.createdToday = 0;
            acct.redeemedToday = 0;
        }

        TierLimits storage limits = $.tiers[acct.tier];
        uint256 used = isCreate ? acct.createdToday : acct.redeemedToday;
        uint256 left = _left(isCreate ? limits.dailyCreate : limits.dailyRedeem, used);
        if (amount > left) revert LimitExceeded(account, amount, left);

        // used + amount <= the tier limit, which is a uint128, so the cast cannot fail.
        uint128 newUsed = SafeCast.toUint128(used + amount);
        if (isCreate) {
            acct.createdToday = newUsed;
        } else {
            acct.redeemedToday = newUsed;
        }
    }

    function _isParticipant(Account storage acct) private view returns (bool) {
        return acct.active && (acct.kind == Kind.Participant || acct.kind == Kind.Both);
    }

    /// @dev Saturates at zero: a tier lowered below today's usage leaves nothing, not an underflow.
    function _left(uint256 limit, uint256 used) private pure returns (uint256) {
        return limit > used ? limit - used : 0;
    }

    /// @dev UTC day index (L1 section 3.2).
    function _today() private view returns (uint32) {
        return SafeCast.toUint32(block.timestamp / 1 days);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Roles.UPGRADER_ROLE) {}

    function _getRegistryStorage() private pure returns (RegistryStorage storage $) {
        assembly {
            $.slot := REGISTRY_STORAGE_LOCATION
        }
    }
}
