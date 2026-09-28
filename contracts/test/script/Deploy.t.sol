// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {KandaToken} from "../../src/token/KandaToken.sol";
import {ParticipantRegistry} from "../../src/registry/ParticipantRegistry.sol";
import {BasketVault} from "../../src/vault/BasketVault.sol";
import {IBasketVault} from "../../src/interfaces/IBasketVault.sol";
import {IParticipantRegistry} from "../../src/interfaces/IParticipantRegistry.sol";
import {Roles} from "../../src/governance/Roles.sol";
import {KandaDeployer} from "../../script/lib/KandaDeployer.sol";
import {DeployConfig, DeployConfigLib, TierConfig} from "../../script/lib/DeployConfig.sol";
import {Deployment, Grant, RoleMap} from "../../script/lib/RoleMap.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockGoldToken} from "../mocks/MockGoldToken.sol";
import {BasketVaultV2Mock} from "../mocks/BasketVaultV2Mock.sol";

/// @notice Deploy, WireRoles and VerifyRoles logic (L1 section 7): the role map is wired exactly, the deployer keeps
///         nothing, bad configs abort, and the deployed system works end to end through the timelock.
contract DeployTest is Test, KandaDeployer {
    address internal deployer = makeAddr("deployer");
    DeployConfig internal cfg;
    MockERC20 internal usdc;
    MockGoldToken internal gold;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        gold = new MockGoldToken();
        cfg.chainId = block.chainid;
        cfg.usdc = address(usdc);
        cfg.goldToken = address(gold);
        cfg.goldDecimals = 18;
        cfg.adminSafe = makeAddr("adminSafe");
        cfg.opsSafe = makeAddr("opsSafe");
        cfg.complianceSafe = makeAddr("complianceSafe");
        cfg.guardianSafe = makeAddr("guardianSafe");
        cfg.treasurySafe = makeAddr("treasurySafe");
        cfg.pauseBot = makeAddr("pauseBot");
        cfg.releaser = makeAddr("releaser");
        cfg.feeRecipient = cfg.treasurySafe;
        cfg.timelockDelay = 300;
        cfg.supplyCap = 1_000_000e18;
        cfg.feeBps = 10;
        cfg.usdQtyPerUnit = 700_000;
        cfg.goldQtyPerUnit = 70_000_000_000_000;
        cfg.tiers.push(TierConfig(1, 50_000e18, 50_000e18));
        cfg.tiers.push(TierConfig(2, 250_000e18, 250_000e18));
    }

    function _deployAsDeployer() internal returns (Deployment memory d) {
        vm.startPrank(deployer);
        d = _deployAll(cfg, deployer);
        vm.stopPrank();
    }

    // =============================================================
    // Role map
    // =============================================================

    function test_deploy_passesVerifyRoles() public {
        Deployment memory d = _deployAsDeployer();
        _verifyRoles(cfg, d, deployer);
    }

    function test_deploy_everyMappedGrantHeld() public {
        Deployment memory d = _deployAsDeployer();
        Grant[] memory g = RoleMap.grants(cfg, d);
        for (uint256 i; i < g.length; ++i) {
            assertTrue(IAccessControl(g[i].target).hasRole(g[i].role, g[i].holder), "mapped grant missing");
        }
    }

    function test_deploy_deployerKeepsNoRole() public {
        Deployment memory d = _deployAsDeployer();
        address[4] memory targets = [d.kandaToken, d.registry, d.vault, d.timelock];
        bytes32[] memory roles = RoleMap.roles();
        bytes32[] memory tlRoles = RoleMap.timelockRoles();
        for (uint256 t; t < targets.length; ++t) {
            for (uint256 r; r < roles.length; ++r) {
                assertFalse(IAccessControl(targets[t]).hasRole(roles[r], deployer), "deployer kept a role");
            }
            for (uint256 r; r < tlRoles.length; ++r) {
                assertFalse(IAccessControl(targets[t]).hasRole(tlRoles[r], deployer), "deployer kept a role");
            }
        }
    }

    function test_deploy_timelockConfigured() public {
        Deployment memory d = _deployAsDeployer();
        TimelockController tl = TimelockController(payable(d.timelock));
        assertEq(tl.getMinDelay(), 300);
        assertTrue(tl.hasRole(tl.PROPOSER_ROLE(), cfg.adminSafe));
        assertTrue(tl.hasRole(tl.CANCELLER_ROLE(), cfg.adminSafe));
        assertTrue(tl.hasRole(tl.EXECUTOR_ROLE(), address(0)), "executor is open");
        assertTrue(tl.hasRole(tl.DEFAULT_ADMIN_ROLE(), d.timelock), "timelock administers itself");
        // The hashed names in RoleMap match the timelock's own constants.
        Grant[] memory g = RoleMap.timelockGrants(cfg, d);
        assertEq(g[0].role, tl.PROPOSER_ROLE());
        assertEq(g[1].role, tl.CANCELLER_ROLE());
        assertEq(g[2].role, tl.EXECUTOR_ROLE());
    }

    function test_verifyRoles_catchesExtraGrant() public {
        Deployment memory d = _deployAsDeployer();
        vm.prank(d.timelock);
        KandaToken(d.kandaToken).grantRole(Roles.PAUSER_ROLE, cfg.opsSafe);
        vm.expectRevert(
            abi.encodeWithSelector(RoleMismatch.selector, d.kandaToken, Roles.PAUSER_ROLE, cfg.opsSafe, false)
        );
        this.verifyRolesExternal(d);
    }

    function test_verifyRoles_catchesMissingGrant() public {
        Deployment memory d = _deployAsDeployer();
        vm.prank(d.timelock);
        KandaToken(d.kandaToken).revokeRole(Roles.MINTER_ROLE, d.vault);
        vm.expectRevert(abi.encodeWithSelector(RoleMismatch.selector, d.kandaToken, Roles.MINTER_ROLE, d.vault, true));
        this.verifyRolesExternal(d);
    }

    function verifyRolesExternal(Deployment memory d) external view {
        _verifyRoles(cfg, d, deployer);
    }

    // =============================================================
    // Deployed state
    // =============================================================

    function test_deploy_setsTokenBasketAndTiers() public {
        Deployment memory d = _deployAsDeployer();
        assertEq(KandaToken(d.kandaToken).symbol(), "KND");

        (uint32 version, IBasketVault.Leg[] memory legs) = BasketVault(d.vault).legs();
        assertEq(version, 1);
        assertEq(legs[0].asset, address(usdc));
        assertEq(legs[0].qtyPerUnit, 700_000);
        assertEq(legs[1].asset, address(gold));
        assertEq(legs[1].qtyPerUnit, 70_000_000_000_000);

        address ap = makeAddr("ap");
        vm.prank(cfg.opsSafe);
        ParticipantRegistry(d.registry).setAccount(ap, IParticipantRegistry.Kind.Participant, 2, true);
        (uint256 create,) = ParticipantRegistry(d.registry).remaining(ap);
        assertEq(create, 250_000e18);
    }

    function test_deploy_implementationsLocked() public {
        Deployment memory d = _deployAsDeployer();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        KandaToken(d.kandaTokenImpl).initialize(deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ParticipantRegistry(d.registryImpl).initialize(deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        BasketVault(d.vaultImpl).initialize(deployer, address(1), address(1), new IBasketVault.Leg[](0), 0, 0, deployer);
    }

    /// @dev Proves the wiring end to end: Ops registers a participant, the vault mints (MINTER_ROLE) and consumes the
    ///      limit (LIMITS_CONSUMER_ROLE), the fee reaches the treasury, and an upgrade goes through the timelock.
    function test_deploy_endToEndCreateAndTimelockUpgrade() public {
        Deployment memory d = _deployAsDeployer();
        address ap = makeAddr("ap");
        vm.prank(cfg.opsSafe);
        ParticipantRegistry(d.registry).setAccount(ap, IParticipantRegistry.Kind.Participant, 1, true);

        usdc.mint(ap, 700e6);
        gold.mint(ap, 0.07e18);
        vm.startPrank(ap);
        usdc.approve(d.vault, type(uint256).max);
        gold.approve(d.vault, type(uint256).max);
        uint256 out = BasketVault(d.vault).createInKind(1000e18, 0, ap);
        vm.stopPrank();
        assertEq(out, 999e18);
        assertEq(KandaToken(d.kandaToken).balanceOf(cfg.treasurySafe), 1e18);

        // Upgrade the vault: Admin Safe schedules on the timelock, anyone executes after the delay.
        TimelockController tl = TimelockController(payable(d.timelock));
        address v2 = address(new BasketVaultV2Mock());
        bytes memory call = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", v2, "");
        vm.prank(cfg.adminSafe);
        tl.schedule(d.vault, 0, call, bytes32(0), bytes32(0), 300);
        vm.expectRevert();
        tl.execute(d.vault, 0, call, bytes32(0), bytes32(0));
        vm.warp(block.timestamp + 300);
        tl.execute(d.vault, 0, call, bytes32(0), bytes32(0));
        assertEq(BasketVaultV2Mock(d.vault).version(), 2);
    }

    // =============================================================
    // Config checks
    // =============================================================

    function test_deploy_abortsOnGoldDecimalsMismatch() public {
        cfg.goldDecimals = 6;
        vm.expectRevert(abi.encodeWithSelector(GoldDecimalsMismatch.selector, 6, 18));
        this.deployExternal();
    }

    function test_deploy_abortsWhenGoldQtyUnset() public {
        cfg.goldQtyPerUnit = 0;
        vm.expectRevert(GoldQtyNotSet.selector);
        this.deployExternal();
    }

    function test_deploy_abortsOnZeroAddressPlaceholder() public {
        cfg.guardianSafe = address(0);
        vm.expectRevert(abi.encodeWithSelector(ZeroConfigAddress.selector, "safes.guardian"));
        this.deployExternal();
    }

    function test_deploy_abortsOnWrongChain() public {
        cfg.chainId = 8453;
        vm.expectRevert(abi.encodeWithSelector(ChainIdMismatch.selector, 8453, block.chainid));
        this.deployExternal();
    }

    function deployExternal() external returns (Deployment memory) {
        return _deployAll(cfg, deployer);
    }

    function test_config_parsesMainnetFile() public view {
        DeployConfig memory c = DeployConfigLib.parse(vm.readFile(string.concat(vm.projectRoot(), "/config/base.json")));
        assertEq(c.chainId, 8453);
        assertEq(c.supplyCap, 1_000_000e18);
        assertEq(c.feeBps, 10);
        assertEq(c.usdQtyPerUnit, 700_000);
        assertEq(c.goldDecimals, 18);
        assertEq(c.tiers.length, 2);
        assertEq(c.tiers[1].tier, 2);
        assertEq(c.tiers[1].dailyCreate, 250_000e18);
        assertEq(c.goldToken, 0xe908475f8Beb7A138B0dc6eb5A05cb27068ffB9A, "DGLD, ADR-010");
    }

    function test_config_networkNames() public {
        assertEq(DeployConfigLib.networkName(84_532), "base-sepolia");
        assertEq(DeployConfigLib.networkName(8453), "base");
        vm.expectRevert(abi.encodeWithSelector(DeployConfigLib.UnsupportedChain.selector, 1));
        this.networkNameExternal(1);
    }

    function networkNameExternal(uint256 chainId) external pure returns (string memory) {
        return DeployConfigLib.networkName(chainId);
    }
}
