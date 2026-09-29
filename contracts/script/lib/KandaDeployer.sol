// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {KandaToken} from "../../src/token/KandaToken.sol";
import {ParticipantRegistry} from "../../src/registry/ParticipantRegistry.sol";
import {BasketVault} from "../../src/vault/BasketVault.sol";
import {IBasketVault} from "../../src/interfaces/IBasketVault.sol";
import {IParticipantRegistry} from "../../src/interfaces/IParticipantRegistry.sol";
import {Roles} from "../../src/governance/Roles.sol";
import {DeployConfig} from "./DeployConfig.sol";
import {Deployment, Grant, RoleMap} from "./RoleMap.sol";

/// @title KandaDeployer
/// @notice Deploy, WireRoles and VerifyRoles logic shared by the scripts and their tests (L1 section 7). The caller
///         (broadcaster in a script, pranked deployer in a test) must be `deployer`.
/// @dev P0 steps: 1 TimelockController, 2 KandaToken, 3 ParticipantRegistry, 4 BasketVault, then tiers, WireRoles
///      and VerifyRoles. NAVOracle, PaymentEscrow and ZapRouter (steps 5 to 7) are added with their P1 tasks.
abstract contract KandaDeployer {
    error ChainIdMismatch(uint256 configChainId, uint256 chainId);
    error ZeroConfigAddress(string field);
    error GoldDecimalsMismatch(uint8 configured, uint8 actual);
    error GoldQtyNotSet();
    error RoleMismatch(address target, bytes32 role, address account, bool expected);

    /// @notice Full P0 deployment: validate, deploy, set tiers, wire roles, renounce, verify.
    function _deployAll(DeployConfig memory cfg, address deployer) internal returns (Deployment memory d) {
        _validate(cfg);
        d = _deployContracts(cfg, deployer);
        _setTiers(cfg, d, deployer);
        _wireRoles(cfg, d, deployer);
        _verifyRoles(cfg, d, deployer);
    }

    /// @notice Refuse configs that would deploy something wrong: wrong chain, zero placeholders, gold decimals that
    ///         differ from the token (L1 section 7), or a gold quantity not yet set.
    function _validate(DeployConfig memory cfg) internal view {
        if (cfg.chainId != block.chainid) revert ChainIdMismatch(cfg.chainId, block.chainid);
        _requireSet(cfg.usdc, "usdc");
        _requireSet(cfg.goldToken, "goldToken");
        _requireSet(cfg.adminSafe, "safes.admin");
        _requireSet(cfg.opsSafe, "safes.ops");
        _requireSet(cfg.complianceSafe, "safes.compliance");
        _requireSet(cfg.guardianSafe, "safes.guardian");
        _requireSet(cfg.treasurySafe, "safes.treasury");
        _requireSet(cfg.pauseBot, "pauseBot");
        _requireSet(cfg.releaser, "releaser");
        _requireSet(cfg.feeRecipient, "feeRecipient");
        uint8 actual = IERC20Metadata(cfg.goldToken).decimals();
        if (actual != cfg.goldDecimals) revert GoldDecimalsMismatch(cfg.goldDecimals, actual);
        if (cfg.goldQtyPerUnit == 0) revert GoldQtyNotSet();
    }

    /// @notice Steps 1 to 4. Every proxy is initialized with `deployer` as its only admin until WireRoles.
    function _deployContracts(DeployConfig memory cfg, address deployer) internal returns (Deployment memory d) {
        address[] memory proposers = new address[](1);
        proposers[0] = cfg.adminSafe;
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open executor (L1 section 7)
        d.timelock = address(new TimelockController(cfg.timelockDelay, proposers, executors, address(0)));

        d.kandaTokenImpl = address(new KandaToken());
        d.kandaToken = address(new ERC1967Proxy(d.kandaTokenImpl, abi.encodeCall(KandaToken.initialize, (deployer))));

        d.registryImpl = address(new ParticipantRegistry());
        d.registry =
            address(new ERC1967Proxy(d.registryImpl, abi.encodeCall(ParticipantRegistry.initialize, (deployer))));

        IBasketVault.Leg[] memory legs = new IBasketVault.Leg[](2);
        legs[0] = IBasketVault.Leg(cfg.usdc, cfg.usdQtyPerUnit);
        legs[1] = IBasketVault.Leg(cfg.goldToken, cfg.goldQtyPerUnit);
        d.vaultImpl = address(new BasketVault());
        d.vault = address(
            new ERC1967Proxy(
                d.vaultImpl,
                abi.encodeCall(
                    BasketVault.initialize,
                    (deployer, d.kandaToken, d.registry, legs, cfg.supplyCap, cfg.feeBps, cfg.feeRecipient)
                )
            )
        );
    }

    /// @notice Set the tier limits from config. The deployer holds LIMITS_ADMIN_ROLE only for this step.
    function _setTiers(DeployConfig memory cfg, Deployment memory d, address deployer) internal {
        ParticipantRegistry registry = ParticipantRegistry(d.registry);
        registry.grantRole(Roles.LIMITS_ADMIN_ROLE, deployer);
        for (uint256 i; i < cfg.tiers.length; ++i) {
            registry.setTier(
                cfg.tiers[i].tier, IParticipantRegistry.TierLimits(cfg.tiers[i].dailyCreate, cfg.tiers[i].dailyRedeem)
            );
        }
        registry.renounceRole(Roles.LIMITS_ADMIN_ROLE, deployer);
    }

    /// @notice WireRoles (step 8): grant every row of the role map, then renounce every deployer role.
    function _wireRoles(DeployConfig memory cfg, Deployment memory d, address deployer) internal {
        Grant[] memory g = RoleMap.grants(cfg, d);
        for (uint256 i; i < g.length; ++i) {
            IAccessControl(g[i].target).grantRole(g[i].role, g[i].holder);
        }
        address[3] memory targets = [d.kandaToken, d.registry, d.vault];
        for (uint256 i; i < targets.length; ++i) {
            IAccessControl(targets[i]).renounceRole(RoleMap.DEFAULT_ADMIN_ROLE, deployer);
        }
    }

    /// @notice VerifyRoles (step 9): every known address holds exactly its mapped roles on every contract.
    function _verifyRoles(DeployConfig memory cfg, Deployment memory d, address deployer) internal view {
        address[] memory known = RoleMap.knownAddresses(cfg, d, deployer);
        _checkMatrix(RoleMap.grants(cfg, d), [d.kandaToken, d.registry, d.vault], RoleMap.roles(), known);

        Grant[] memory tl = RoleMap.timelockGrants(cfg, d);
        bytes32[] memory tlRoles = RoleMap.timelockRoles();
        for (uint256 r; r < tlRoles.length; ++r) {
            for (uint256 k; k < known.length; ++k) {
                _checkOne(tl, d.timelock, tlRoles[r], known[k]);
            }
        }
    }

    function _checkMatrix(
        Grant[] memory expected,
        address[3] memory targets,
        bytes32[] memory roles,
        address[] memory known
    ) private view {
        for (uint256 t; t < targets.length; ++t) {
            for (uint256 r; r < roles.length; ++r) {
                for (uint256 k; k < known.length; ++k) {
                    _checkOne(expected, targets[t], roles[r], known[k]);
                }
            }
        }
    }

    function _checkOne(Grant[] memory expected, address target, bytes32 role, address account) private view {
        bool want = RoleMap.isExpected(expected, target, role, account);
        if (IAccessControl(target).hasRole(role, account) != want) revert RoleMismatch(target, role, account, want);
    }

    function _requireSet(address value, string memory field) private pure {
        if (value == address(0)) revert ZeroConfigAddress(field);
    }
}
