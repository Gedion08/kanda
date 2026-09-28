// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Roles} from "../../src/governance/Roles.sol";
import {DeployConfig} from "./DeployConfig.sol";

/// @notice Addresses produced by Deploy.s.sol (written to deployments/<network>.json).
struct Deployment {
    address timelock;
    address kandaToken;
    address kandaTokenImpl;
    address registry;
    address registryImpl;
    address vault;
    address vaultImpl;
}

/// @notice One expected role assignment.
struct Grant {
    address target;
    bytes32 role;
    address holder;
}

/// @title RoleMap
/// @notice The ADD section 4 role map for the P0 contracts, as data. WireRoles grants from it, VerifyRoles checks
///         against it, and the deploy tests assert on it, so the three cannot drift apart. PaymentEscrow
///         (RELEASER_ROLE, ARBITER_ROLE), NAVOracle and ZapRouter rows arrive with their P1 tasks.
library RoleMap {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @notice Every expected (contract, role, holder) row for the AccessControl contracts.
    function grants(DeployConfig memory cfg, Deployment memory d) internal pure returns (Grant[] memory g) {
        g = new Grant[](18);
        uint256 i;
        // KandaToken
        g[i++] = Grant(d.kandaToken, DEFAULT_ADMIN_ROLE, d.timelock);
        g[i++] = Grant(d.kandaToken, Roles.UPGRADER_ROLE, d.timelock);
        g[i++] = Grant(d.kandaToken, Roles.MINTER_ROLE, d.vault);
        g[i++] = Grant(d.kandaToken, Roles.PAUSER_ROLE, cfg.guardianSafe);
        g[i++] = Grant(d.kandaToken, Roles.PAUSER_ROLE, cfg.pauseBot);
        g[i++] = Grant(d.kandaToken, Roles.UNPAUSER_ROLE, cfg.adminSafe);
        g[i++] = Grant(d.kandaToken, Roles.COMPLIANCE_ROLE, cfg.complianceSafe);
        // ParticipantRegistry
        g[i++] = Grant(d.registry, DEFAULT_ADMIN_ROLE, d.timelock);
        g[i++] = Grant(d.registry, Roles.UPGRADER_ROLE, d.timelock);
        g[i++] = Grant(d.registry, Roles.LIMITS_ADMIN_ROLE, d.timelock);
        g[i++] = Grant(d.registry, Roles.PARTICIPANT_MANAGER_ROLE, cfg.opsSafe);
        g[i++] = Grant(d.registry, Roles.LIMITS_CONSUMER_ROLE, d.vault);
        // BasketVault
        g[i++] = Grant(d.vault, DEFAULT_ADMIN_ROLE, d.timelock);
        g[i++] = Grant(d.vault, Roles.UPGRADER_ROLE, d.timelock);
        g[i++] = Grant(d.vault, Roles.LIMITS_ADMIN_ROLE, d.timelock);
        g[i++] = Grant(d.vault, Roles.PAUSER_ROLE, cfg.guardianSafe);
        g[i++] = Grant(d.vault, Roles.PAUSER_ROLE, cfg.pauseBot);
        g[i++] = Grant(d.vault, Roles.UNPAUSER_ROLE, cfg.adminSafe);
    }

    /// @notice Every expected TimelockController row: Admin Safe proposes and cancels, anyone executes, and the
    ///         timelock administers itself (no external admin).
    function timelockGrants(DeployConfig memory cfg, Deployment memory d) internal pure returns (Grant[] memory g) {
        g = new Grant[](4);
        g[0] = Grant(d.timelock, keccak256("PROPOSER_ROLE"), cfg.adminSafe);
        g[1] = Grant(d.timelock, keccak256("CANCELLER_ROLE"), cfg.adminSafe);
        g[2] = Grant(d.timelock, keccak256("EXECUTOR_ROLE"), address(0));
        g[3] = Grant(d.timelock, DEFAULT_ADMIN_ROLE, d.timelock);
    }

    /// @notice Every role checked on the AccessControl contracts.
    function roles() internal pure returns (bytes32[] memory r) {
        r = new bytes32[](12);
        r[0] = DEFAULT_ADMIN_ROLE;
        r[1] = Roles.UPGRADER_ROLE;
        r[2] = Roles.LIMITS_ADMIN_ROLE;
        r[3] = Roles.MINTER_ROLE;
        r[4] = Roles.PAUSER_ROLE;
        r[5] = Roles.UNPAUSER_ROLE;
        r[6] = Roles.COMPLIANCE_ROLE;
        r[7] = Roles.PARTICIPANT_MANAGER_ROLE;
        r[8] = Roles.ARBITER_ROLE;
        r[9] = Roles.RELEASER_ROLE;
        r[10] = Roles.LIMITS_CONSUMER_ROLE;
        r[11] = Roles.ORACLE_ADMIN_ROLE;
    }

    /// @notice Every role checked on the TimelockController.
    function timelockRoles() internal pure returns (bytes32[] memory r) {
        r = new bytes32[](4);
        r[0] = DEFAULT_ADMIN_ROLE;
        r[1] = keccak256("PROPOSER_ROLE");
        r[2] = keccak256("CANCELLER_ROLE");
        r[3] = keccak256("EXECUTOR_ROLE");
    }

    /// @notice Every address the check covers: each must hold exactly its mapped roles and nothing else.
    /// @dev AccessControl cannot list members, so a role granted to an address outside this list is invisible
    ///      here. The indexer's RoleGranted watch covers that (L7 section 5).
    function knownAddresses(DeployConfig memory cfg, Deployment memory d, address deployer)
        internal
        pure
        returns (address[] memory a)
    {
        a = new address[](14);
        a[0] = deployer;
        a[1] = cfg.adminSafe;
        a[2] = cfg.opsSafe;
        a[3] = cfg.complianceSafe;
        a[4] = cfg.guardianSafe;
        a[5] = cfg.treasurySafe;
        a[6] = cfg.pauseBot;
        a[7] = cfg.releaser;
        a[8] = cfg.feeRecipient;
        a[9] = d.timelock;
        a[10] = d.kandaToken;
        a[11] = d.registry;
        a[12] = d.vault;
        a[13] = address(0);
    }

    /// @notice Whether (target, role, holder) is in `expected`.
    function isExpected(Grant[] memory expected, address target, bytes32 role, address holder)
        internal
        pure
        returns (bool)
    {
        for (uint256 i; i < expected.length; ++i) {
            if (expected[i].target == target && expected[i].role == role && expected[i].holder == holder) return true;
        }
        return false;
    }
}
