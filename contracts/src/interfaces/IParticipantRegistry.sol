// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IParticipantRegistry
/// @notice Who may use the primary market and the escrow, with tiered daily limits. Spec: L1 section 3.2.
interface IParticipantRegistry {
    /// @notice What an account may do: Participant uses the vault, Partner uses the escrow, Both does both.
    enum Kind {
        None,
        Participant,
        Partner,
        Both
    }

    /// @notice Daily limits for a tier, in KND base units.
    struct TierLimits {
        uint128 dailyCreate;
        uint128 dailyRedeem;
    }

    /// @notice An account's registration and its consumption for `day`.
    struct Account {
        Kind kind;
        uint8 tier;
        bool active;
        uint32 day;
        uint128 createdToday;
        uint128 redeemedToday;
    }

    /// @notice Emitted when an account's kind, tier or active flag is set.
    event AccountSet(address indexed account, Kind kind, uint8 tier, bool active);
    /// @notice Emitted when a tier's daily limits are set.
    event TierSet(uint8 indexed tier, uint128 dailyCreate, uint128 dailyRedeem);

    /// @notice `account` is not an active account of the kind the call needs.
    error NotActive(address account);
    /// @notice `requested` exceeds what `account` has left today.
    error LimitExceeded(address account, uint256 requested, uint256 remaining);
    /// @notice `tier` has never been set with setTier.
    error UnknownTier(uint8 tier);
    /// @notice A required address argument is zero.
    error ZeroAddress();

    /// @notice Register or update `account`. PARTICIPANT_MANAGER_ROLE only. Today's consumption is kept.
    /// @param account Account to set; must not be zero.
    /// @param kind What the account may do.
    /// @param tier Tier whose limits apply; must have been set with setTier.
    /// @param active Whether the account may act.
    function setAccount(address account, Kind kind, uint8 tier, bool active) external;

    /// @notice Set a tier's daily limits. LIMITS_ADMIN_ROLE (timelock) only. A tier exists once set.
    /// @param tier Tier number.
    /// @param limits Daily create and redeem limits in KND base units.
    function setTier(uint8 tier, TierLimits calldata limits) external;

    /// @notice Record `amount` of creation by `account` against today's limit. LIMITS_CONSUMER_ROLE only.
    /// @dev Reverts NotActive unless `account` is an active participant, LimitExceeded if over today's limit.
    /// @param account Participant creating KND.
    /// @param amount Gross KND amount in base units.
    function consumeCreate(address account, uint256 amount) external;

    /// @notice Record `amount` of redemption by `account` against today's limit. LIMITS_CONSUMER_ROLE only.
    /// @dev Reverts NotActive unless `account` is an active participant, LimitExceeded if over today's limit.
    /// @param account Participant redeeming KND.
    /// @param amount Gross KND amount in base units.
    function consumeRedeem(address account, uint256 amount) external;

    /// @notice Whether `account` is active with kind Participant or Both.
    /// @param account Account to check.
    /// @return True if it may use the primary market.
    function isParticipant(address account) external view returns (bool);

    /// @notice Whether `account` is active with kind Partner or Both.
    /// @param account Account to check.
    /// @return True if it may use the escrow.
    function isPartner(address account) external view returns (bool);

    /// @notice What `account` may still create and redeem today (UTC day). Zero for anyone not an active participant.
    /// @param account Account to check.
    /// @return create Remaining creation in KND base units.
    /// @return redeem Remaining redemption in KND base units.
    function remaining(address account) external view returns (uint256 create, uint256 redeem);
}
