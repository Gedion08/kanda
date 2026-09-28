// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ParticipantRegistry} from "../../src/registry/ParticipantRegistry.sol";
import {IParticipantRegistry} from "../../src/interfaces/IParticipantRegistry.sol";
import {Roles} from "../../src/governance/Roles.sol";
import {ParticipantRegistryV2Mock} from "../mocks/ParticipantRegistryV2Mock.sol";

/// @notice Shared setup: a registry proxy with the P1 tiers (L1 section 4) and every role held by a separate key.
abstract contract ParticipantRegistryTestBase is Test {
    /// @dev keccak256(abi.encode(uint256(keccak256("kanda.storage.ParticipantRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant REGISTRY_STORAGE_LOCATION =
        0x532998f640c1c55ad4fcd78d62f693bc8582b3df1029f60449125e88fb695e00;

    uint128 internal constant TIER1_LIMIT = 50_000e18;
    uint128 internal constant TIER2_LIMIT = 250_000e18;
    /// @dev A fixed UTC midnight (2026-09-28) so day arithmetic in tests is exact.
    uint256 internal constant DAY0 = 1_790_553_600;

    ParticipantRegistry internal registry;
    ParticipantRegistry internal implementation;

    address internal admin = makeAddr("admin");
    address internal limitsAdmin = makeAddr("limitsAdmin");
    address internal manager = makeAddr("manager");
    address internal vault = makeAddr("vault");
    address internal upgrader = makeAddr("upgrader");
    address internal stranger = makeAddr("stranger");
    address internal ap = makeAddr("authorizedParticipant");
    address internal partner = makeAddr("partner");

    function setUp() public virtual {
        vm.warp(DAY0 + 9 hours);

        implementation = new ParticipantRegistry();
        registry = ParticipantRegistry(
            address(new ERC1967Proxy(address(implementation), abi.encodeCall(ParticipantRegistry.initialize, (admin))))
        );

        vm.startPrank(admin);
        registry.grantRole(Roles.LIMITS_ADMIN_ROLE, limitsAdmin);
        registry.grantRole(Roles.PARTICIPANT_MANAGER_ROLE, manager);
        registry.grantRole(Roles.LIMITS_CONSUMER_ROLE, vault);
        registry.grantRole(Roles.UPGRADER_ROLE, upgrader);
        vm.stopPrank();

        _setTier(1, TIER1_LIMIT, TIER1_LIMIT);
        _setTier(2, TIER2_LIMIT, TIER2_LIMIT);
        _setAccount(ap, IParticipantRegistry.Kind.Participant, 1, true);
        _setAccount(partner, IParticipantRegistry.Kind.Partner, 1, true);
    }

    function _setTier(uint8 tier, uint128 dailyCreate, uint128 dailyRedeem) internal {
        vm.prank(limitsAdmin);
        registry.setTier(tier, IParticipantRegistry.TierLimits(dailyCreate, dailyRedeem));
    }

    function _setAccount(address account, IParticipantRegistry.Kind kind, uint8 tier, bool active) internal {
        vm.prank(manager);
        registry.setAccount(account, kind, tier, active);
    }

    function _consumeCreate(address account, uint256 amount) internal {
        vm.prank(vault);
        registry.consumeCreate(account, amount);
    }

    function _consumeRedeem(address account, uint256 amount) internal {
        vm.prank(vault);
        registry.consumeRedeem(account, amount);
    }

    function _expectMissingRole(address account, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role));
    }
}

/// @notice Unit tests for ParticipantRegistry, L1 section 3.2: roles, tiers, accounts, daily limits and the UTC
///         day rollover.
contract ParticipantRegistryTest is ParticipantRegistryTestBase {
    // =============================================================
    // Initialization
    // =============================================================

    function test_initialize_grantsOnlyDefaultAdmin() public {
        ParticipantRegistry fresh = ParticipantRegistry(
            address(new ERC1967Proxy(address(implementation), abi.encodeCall(ParticipantRegistry.initialize, (admin))))
        );
        assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(fresh.hasRole(Roles.LIMITS_ADMIN_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.PARTICIPANT_MANAGER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.LIMITS_CONSUMER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.UPGRADER_ROLE, admin));
    }

    function test_initialize_revertsOnZeroAdmin() public {
        vm.expectRevert(IParticipantRegistry.ZeroAddress.selector);
        new ERC1967Proxy(address(implementation), abi.encodeCall(ParticipantRegistry.initialize, (address(0))));
    }

    function test_initialize_revertsWhenCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        registry.initialize(stranger);
    }

    function test_implementation_initializersDisabled() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(stranger);
    }

    // =============================================================
    // setTier
    // =============================================================

    function test_setTier_setsAndEmits() public {
        vm.expectEmit(address(registry));
        emit IParticipantRegistry.TierSet(3, 10e18, 20e18);
        _setTier(3, 10e18, 20e18);

        _setAccount(stranger, IParticipantRegistry.Kind.Participant, 3, true);
        (uint256 create, uint256 redeem) = registry.remaining(stranger);
        assertEq(create, 10e18);
        assertEq(redeem, 20e18);
    }

    function test_setTier_overwritesLimits() public {
        _setTier(1, 1e18, 2e18);
        (uint256 create, uint256 redeem) = registry.remaining(ap);
        assertEq(create, 1e18);
        assertEq(redeem, 2e18);
    }

    function test_setTier_zeroLimitsIsValidTier() public {
        _setTier(0, 0, 0);
        _setAccount(stranger, IParticipantRegistry.Kind.Participant, 0, true);
        (uint256 create, uint256 redeem) = registry.remaining(stranger);
        assertEq(create, 0);
        assertEq(redeem, 0);
    }

    function test_setTier_revertsWithoutLimitsAdminRole() public {
        _expectMissingRole(manager, Roles.LIMITS_ADMIN_ROLE);
        vm.prank(manager);
        registry.setTier(3, IParticipantRegistry.TierLimits(1, 1));
    }

    function test_setTier_revertsForAdminWithoutLimitsAdminRole() public {
        _expectMissingRole(admin, Roles.LIMITS_ADMIN_ROLE);
        vm.prank(admin);
        registry.setTier(3, IParticipantRegistry.TierLimits(1, 1));
    }

    // =============================================================
    // setAccount
    // =============================================================

    function test_setAccount_setsAndEmits() public {
        vm.expectEmit(address(registry));
        emit IParticipantRegistry.AccountSet(stranger, IParticipantRegistry.Kind.Both, 2, true);
        _setAccount(stranger, IParticipantRegistry.Kind.Both, 2, true);

        assertTrue(registry.isParticipant(stranger));
        assertTrue(registry.isPartner(stranger));
        (uint256 create,) = registry.remaining(stranger);
        assertEq(create, TIER2_LIMIT);
    }

    function test_setAccount_revertsWithoutManagerRole() public {
        _expectMissingRole(limitsAdmin, Roles.PARTICIPANT_MANAGER_ROLE);
        vm.prank(limitsAdmin);
        registry.setAccount(stranger, IParticipantRegistry.Kind.Participant, 1, true);
    }

    function test_setAccount_revertsOnZeroAddress() public {
        vm.expectRevert(IParticipantRegistry.ZeroAddress.selector);
        vm.prank(manager);
        registry.setAccount(address(0), IParticipantRegistry.Kind.Participant, 1, true);
    }

    function test_setAccount_revertsOnUnknownTier() public {
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.UnknownTier.selector, 7));
        vm.prank(manager);
        registry.setAccount(stranger, IParticipantRegistry.Kind.Participant, 7, true);
    }

    /// @dev Re-registering must not reset today's usage, or the manager could lift a daily limit by re-setting.
    function test_setAccount_keepsTodaysConsumption() public {
        _consumeCreate(ap, 30_000e18);
        _setAccount(ap, IParticipantRegistry.Kind.Participant, 1, true);
        (uint256 create,) = registry.remaining(ap);
        assertEq(create, 20_000e18);
    }

    function test_setAccount_tierChangeAppliesNewLimitToTodaysUsage() public {
        _consumeCreate(ap, 40_000e18);
        _setAccount(ap, IParticipantRegistry.Kind.Participant, 2, true);
        (uint256 create,) = registry.remaining(ap);
        assertEq(create, TIER2_LIMIT - 40_000e18);
    }

    function test_setAccount_deactivates() public {
        _setAccount(ap, IParticipantRegistry.Kind.Participant, 1, false);
        assertFalse(registry.isParticipant(ap));
        (uint256 create, uint256 redeem) = registry.remaining(ap);
        assertEq(create, 0);
        assertEq(redeem, 0);
    }

    function test_storage_accountAtNamespacedSlot() public view {
        // accounts is the first mapping in the namespace; slot 0 of the struct packs kind | tier | active | day.
        bytes32 slot = keccak256(abi.encode(ap, REGISTRY_STORAGE_LOCATION));
        uint256 packed = uint256(vm.load(address(registry), slot));
        assertEq(packed & 0xff, uint256(IParticipantRegistry.Kind.Participant));
        assertEq((packed >> 8) & 0xff, 1);
        assertEq((packed >> 16) & 0xff, 1);
    }

    // =============================================================
    // isParticipant / isPartner
    // =============================================================

    function test_kinds_truthTable() public {
        address a = makeAddr("kindAccount");
        IParticipantRegistry.Kind[4] memory kinds = [
            IParticipantRegistry.Kind.None,
            IParticipantRegistry.Kind.Participant,
            IParticipantRegistry.Kind.Partner,
            IParticipantRegistry.Kind.Both
        ];
        bool[4] memory participant = [false, true, false, true];
        bool[4] memory partnerKind = [false, false, true, true];

        for (uint256 i; i < 4; ++i) {
            _setAccount(a, kinds[i], 1, true);
            assertEq(registry.isParticipant(a), participant[i], "participant, active");
            assertEq(registry.isPartner(a), partnerKind[i], "partner, active");

            _setAccount(a, kinds[i], 1, false);
            assertFalse(registry.isParticipant(a), "participant, inactive");
            assertFalse(registry.isPartner(a), "partner, inactive");
        }
    }

    function test_unregistered_isNothing() public view {
        assertFalse(registry.isParticipant(stranger));
        assertFalse(registry.isPartner(stranger));
        (uint256 create, uint256 redeem) = registry.remaining(stranger);
        assertEq(create, 0);
        assertEq(redeem, 0);
    }

    // =============================================================
    // consumeCreate
    // =============================================================

    function test_consumeCreate_reducesRemaining() public {
        _consumeCreate(ap, 12_345e18);
        (uint256 create, uint256 redeem) = registry.remaining(ap);
        assertEq(create, TIER1_LIMIT - 12_345e18);
        assertEq(redeem, TIER1_LIMIT);
    }

    function test_consumeCreate_exactlyToLimit() public {
        _consumeCreate(ap, TIER1_LIMIT - 1);
        _consumeCreate(ap, 1);
        (uint256 create,) = registry.remaining(ap);
        assertEq(create, 0);
    }

    function test_consumeCreate_revertsOverLimit() public {
        _consumeCreate(ap, 49_000e18);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, 1000e18 + 1, 1000e18));
        _consumeCreate(ap, 1000e18 + 1);
    }

    function test_consumeCreate_revertsAboveUint128WithoutOverflow() public {
        uint256 huge = uint256(type(uint128).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, huge, TIER1_LIMIT));
        _consumeCreate(ap, huge);
    }

    function test_consumeCreate_revertsAtMaxUint256WithoutOverflow() public {
        _consumeCreate(ap, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, type(uint256).max, TIER1_LIMIT - 1)
        );
        _consumeCreate(ap, type(uint256).max);
    }

    function test_consumeCreate_zeroAmountIsNoop() public {
        _consumeCreate(ap, 0);
        (uint256 create,) = registry.remaining(ap);
        assertEq(create, TIER1_LIMIT);
    }

    function test_consumeCreate_revertsWithoutConsumerRole() public {
        _expectMissingRole(manager, Roles.LIMITS_CONSUMER_ROLE);
        vm.prank(manager);
        registry.consumeCreate(ap, 1);
    }

    function test_consumeCreate_revertsForInactive() public {
        _setAccount(ap, IParticipantRegistry.Kind.Participant, 1, false);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, ap));
        _consumeCreate(ap, 1);
    }

    function test_consumeCreate_revertsForPartnerOnly() public {
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, partner));
        _consumeCreate(partner, 1);
    }

    function test_consumeCreate_revertsForUnregistered() public {
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, stranger));
        _consumeCreate(stranger, 1);
    }

    function test_consumeCreate_worksForBoth() public {
        _setAccount(partner, IParticipantRegistry.Kind.Both, 1, true);
        _consumeCreate(partner, 5e18);
        (uint256 create,) = registry.remaining(partner);
        assertEq(create, TIER1_LIMIT - 5e18);
    }

    function test_consumeCreate_afterTierLowered_remainingIsZero() public {
        _consumeCreate(ap, 40_000e18);
        _setTier(1, 10_000e18, 10_000e18);
        (uint256 create,) = registry.remaining(ap);
        assertEq(create, 0);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, 1, 0));
        _consumeCreate(ap, 1);
    }

    // =============================================================
    // consumeRedeem
    // =============================================================

    function test_consumeRedeem_reducesRemaining() public {
        _consumeRedeem(ap, 7e18);
        (uint256 create, uint256 redeem) = registry.remaining(ap);
        assertEq(create, TIER1_LIMIT);
        assertEq(redeem, TIER1_LIMIT - 7e18);
    }

    function test_consumeRedeem_exactlyToLimit() public {
        _consumeRedeem(ap, TIER1_LIMIT);
        (, uint256 redeem) = registry.remaining(ap);
        assertEq(redeem, 0);
    }

    function test_consumeRedeem_revertsOverLimit() public {
        _consumeRedeem(ap, TIER1_LIMIT);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, 1, 0));
        _consumeRedeem(ap, 1);
    }

    function test_consumeRedeem_revertsWithoutConsumerRole() public {
        _expectMissingRole(stranger, Roles.LIMITS_CONSUMER_ROLE);
        vm.prank(stranger);
        registry.consumeRedeem(ap, 1);
    }

    function test_consumeRedeem_revertsForInactive() public {
        _setAccount(ap, IParticipantRegistry.Kind.Participant, 1, false);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, ap));
        _consumeRedeem(ap, 1);
    }

    function test_consumeRedeem_revertsForPartnerOnly() public {
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, partner));
        _consumeRedeem(partner, 1);
    }

    function test_createAndRedeem_haveSeparateCounters() public {
        _consumeCreate(ap, TIER1_LIMIT);
        _consumeRedeem(ap, TIER1_LIMIT);
        (uint256 create, uint256 redeem) = registry.remaining(ap);
        assertEq(create, 0);
        assertEq(redeem, 0);
    }

    function test_accounts_haveSeparateCounters() public {
        _setAccount(stranger, IParticipantRegistry.Kind.Participant, 1, true);
        _consumeCreate(ap, TIER1_LIMIT);
        (uint256 create,) = registry.remaining(stranger);
        assertEq(create, TIER1_LIMIT);
    }

    // =============================================================
    // UTC day rollover
    // =============================================================

    function test_rollover_lastSecondOfDayStillCounts() public {
        _consumeCreate(ap, TIER1_LIMIT);
        vm.warp(DAY0 + 1 days - 1);
        (uint256 create,) = registry.remaining(ap);
        assertEq(create, 0);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, 1, 0));
        _consumeCreate(ap, 1);
    }

    function test_rollover_resetsAtUtcMidnight() public {
        _consumeCreate(ap, TIER1_LIMIT);
        _consumeRedeem(ap, 10e18);
        vm.warp(DAY0 + 1 days);

        (uint256 create, uint256 redeem) = registry.remaining(ap);
        assertEq(create, TIER1_LIMIT);
        assertEq(redeem, TIER1_LIMIT);

        _consumeCreate(ap, TIER1_LIMIT);
        (create,) = registry.remaining(ap);
        assertEq(create, 0);
    }

    /// @dev A redeem on a new day resets both counters, so yesterday's creation does not leak into today.
    function test_rollover_redeemResetsCreateCounterToo() public {
        _consumeCreate(ap, TIER1_LIMIT);
        vm.warp(DAY0 + 1 days);
        _consumeRedeem(ap, 1e18);
        (uint256 create, uint256 redeem) = registry.remaining(ap);
        assertEq(create, TIER1_LIMIT);
        assertEq(redeem, TIER1_LIMIT - 1e18);
    }

    function test_rollover_afterManyDays() public {
        _consumeCreate(ap, TIER1_LIMIT);
        vm.warp(DAY0 + 400 days + 5 hours);
        _consumeCreate(ap, TIER1_LIMIT);
        (uint256 create,) = registry.remaining(ap);
        assertEq(create, 0);
    }

    // =============================================================
    // UUPS upgrade
    // =============================================================

    function test_upgrade_byUpgraderKeepsState() public {
        _consumeCreate(ap, 1e18);
        ParticipantRegistryV2Mock v2 = new ParticipantRegistryV2Mock();

        vm.prank(upgrader);
        registry.upgradeToAndCall(address(v2), "");

        assertEq(ParticipantRegistryV2Mock(address(registry)).version(), 2);
        assertTrue(registry.isParticipant(ap));
        (uint256 create,) = registry.remaining(ap);
        assertEq(create, TIER1_LIMIT - 1e18);
        assertTrue(registry.hasRole(Roles.LIMITS_CONSUMER_ROLE, vault));
    }

    function test_upgrade_revertsWithoutUpgraderRole() public {
        ParticipantRegistryV2Mock v2 = new ParticipantRegistryV2Mock();
        _expectMissingRole(admin, Roles.UPGRADER_ROLE);
        vm.prank(admin);
        registry.upgradeToAndCall(address(v2), "");
    }

    function test_supportsInterface_accessControl() public view {
        assertTrue(registry.supportsInterface(type(IAccessControl).interfaceId));
    }
}
