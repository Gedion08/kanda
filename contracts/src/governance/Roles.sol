// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Roles
/// @notice Role identifiers from the ADD section 4 role map. WireRoles grants them and VerifyRoles checks them.
/// @dev DEFAULT_ADMIN_ROLE is AccessControl's zero role and is not repeated here.
library Roles {
    /// @notice Upgrade UUPS proxies. Held by the TimelockController.
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Set supply cap, tier caps, fees, basket version, escrow expiry bounds. Held by the TimelockController.
    bytes32 internal constant LIMITS_ADMIN_ROLE = keccak256("LIMITS_ADMIN_ROLE");
    /// @notice Mint and burn KND. Held by BasketVault; in P2 also the CCIP pool and CashDesk.
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Pause KandaToken, BasketVault or PaymentEscrow, or creation only on BasketVault.
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Unpause, including creation on BasketVault. Held by the Admin Safe.
    bytes32 internal constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    /// @notice Block and unblock addresses. Held by the Compliance Safe.
    bytes32 internal constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    /// @notice Add participants and set limits within tier caps. Held by the Ops Safe.
    bytes32 internal constant PARTICIPANT_MANAGER_ROLE = keccak256("PARTICIPANT_MANAGER_ROLE");
    /// @notice Resolve disputed escrow intents. Held by the Ops Safe.
    bytes32 internal constant ARBITER_ROLE = keccak256("ARBITER_ROLE");
    /// @notice Release Locked escrow intents. Held by the releaser MPC key.
    bytes32 internal constant RELEASER_ROLE = keccak256("RELEASER_ROLE");
    /// @notice Consume participants' daily create and redeem limits. Held by BasketVault; in P2 also CashDesk.
    bytes32 internal constant LIMITS_CONSUMER_ROLE = keccak256("LIMITS_CONSUMER_ROLE");
    /// @notice Change oracle feeds and thresholds. Held by the TimelockController.
    bytes32 internal constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
}
