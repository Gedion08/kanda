// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {PaymentEscrow} from "../../src/payments/PaymentEscrow.sol";
import {KandaToken} from "../../src/token/KandaToken.sol";
import {ParticipantRegistry} from "../../src/registry/ParticipantRegistry.sol";
import {IPaymentEscrow} from "../../src/interfaces/IPaymentEscrow.sol";
import {IKandaToken} from "../../src/interfaces/IKandaToken.sol";
import {IParticipantRegistry} from "../../src/interfaces/IParticipantRegistry.sol";
import {Roles} from "../../src/governance/Roles.sol";
import {PaymentEscrowV2Mock} from "../mocks/PaymentEscrowV2Mock.sol";

/// @notice Shared setup: KND, registry and escrow proxies; two partners holding KND; every role on its own key.
abstract contract PaymentEscrowTestBase is Test {
    uint64 internal constant MIN_EXPIRY = 15 minutes;
    uint64 internal constant MAX_EXPIRY = 24 hours;
    uint128 internal constant AMOUNT = 1000e18;
    bytes32 internal constant ID = keccak256("intent-1");
    bytes32 internal constant META = keccak256("travel-rule-and-invoice");

    KandaToken internal knd;
    ParticipantRegistry internal registry;
    PaymentEscrow internal escrow;
    PaymentEscrow internal implementation;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal compliance = makeAddr("compliance");
    address internal limitsAdmin = makeAddr("limitsAdmin");
    address internal releaser = makeAddr("releaser");
    address internal arbiter = makeAddr("arbiter");
    address internal upgrader = makeAddr("upgrader");
    address internal partnerA = makeAddr("partnerA"); // sender (Kenya)
    address internal partnerB = makeAddr("partnerB"); // receiver (Nigeria)
    address internal participantOnly = makeAddr("participantOnly");
    address internal stranger = makeAddr("stranger");

    function setUp() public virtual {
        knd = KandaToken(
            address(new ERC1967Proxy(address(new KandaToken()), abi.encodeCall(KandaToken.initialize, (admin))))
        );
        registry = ParticipantRegistry(
            address(
                new ERC1967Proxy(
                    address(new ParticipantRegistry()), abi.encodeCall(ParticipantRegistry.initialize, (admin))
                )
            )
        );
        implementation = new PaymentEscrow();
        escrow =
            PaymentEscrow(address(new ERC1967Proxy(address(implementation), _initCall(admin, MIN_EXPIRY, MAX_EXPIRY))));

        vm.startPrank(admin);
        knd.grantRole(Roles.MINTER_ROLE, minter);
        knd.grantRole(Roles.PAUSER_ROLE, pauser);
        knd.grantRole(Roles.COMPLIANCE_ROLE, compliance);
        registry.grantRole(Roles.LIMITS_ADMIN_ROLE, limitsAdmin);
        registry.grantRole(Roles.PARTICIPANT_MANAGER_ROLE, admin);
        escrow.grantRole(Roles.PAUSER_ROLE, pauser);
        escrow.grantRole(Roles.UNPAUSER_ROLE, unpauser);
        escrow.grantRole(Roles.LIMITS_ADMIN_ROLE, limitsAdmin);
        escrow.grantRole(Roles.RELEASER_ROLE, releaser);
        escrow.grantRole(Roles.ARBITER_ROLE, arbiter);
        escrow.grantRole(Roles.UPGRADER_ROLE, upgrader);
        vm.stopPrank();

        vm.prank(limitsAdmin);
        registry.setTier(1, IParticipantRegistry.TierLimits(50_000e18, 50_000e18));
        vm.startPrank(admin);
        registry.setAccount(partnerA, IParticipantRegistry.Kind.Partner, 1, true);
        registry.setAccount(partnerB, IParticipantRegistry.Kind.Partner, 1, true);
        registry.setAccount(participantOnly, IParticipantRegistry.Kind.Participant, 1, true);
        vm.stopPrank();

        _fund(partnerA, 100_000e18);
        _fund(partnerB, 100_000e18);
    }

    function _initCall(address admin_, uint64 minExpiry, uint64 maxExpiry) internal view returns (bytes memory) {
        return abi.encodeCall(PaymentEscrow.initialize, (admin_, address(knd), address(registry), minExpiry, maxExpiry));
    }

    function _fund(address account, uint256 amount) internal {
        vm.prank(minter);
        knd.mint(account, amount);
        vm.prank(account);
        knd.approve(address(escrow), type(uint256).max);
    }

    function _expiry() internal view returns (uint64) {
        return uint64(vm.getBlockTimestamp()) + 1 hours;
    }

    function _lock(bytes32 id) internal returns (uint64 expiry) {
        expiry = _expiry();
        vm.prank(partnerA);
        escrow.lock(id, partnerB, AMOUNT, expiry, META);
    }

    function _status(bytes32 id) internal view returns (IPaymentEscrow.Status) {
        return escrow.intents(id).status;
    }

    function _expectBadStatus(bytes32 id, IPaymentEscrow.Status status) internal {
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.BadStatus.selector, id, status));
    }

    function _expectMissingRole(address account, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role));
    }
}

/// @notice Unit tests for PaymentEscrow, L1 section 3.4: every state transition, every revert, the expiry boundary,
///         pause on every intent path, and the review decisions C-05, C-12 and C-13.
contract PaymentEscrowTest is PaymentEscrowTestBase {
    // =============================================================
    // Initialization
    // =============================================================

    function test_initialize_setsBoundsAndOnlyAdminRole() public {
        vm.expectEmit();
        emit IPaymentEscrow.ExpiryBoundsSet(MIN_EXPIRY, MAX_EXPIRY);
        PaymentEscrow fresh =
            PaymentEscrow(address(new ERC1967Proxy(address(implementation), _initCall(admin, MIN_EXPIRY, MAX_EXPIRY))));
        assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(fresh.hasRole(Roles.RELEASER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.ARBITER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.PAUSER_ROLE, admin));
        assertFalse(fresh.paused());
    }

    function test_initialize_revertsOnZeroAddresses() public {
        bytes[3] memory calls = [
            abi.encodeCall(
                PaymentEscrow.initialize, (address(0), address(knd), address(registry), MIN_EXPIRY, MAX_EXPIRY)
            ),
            abi.encodeCall(PaymentEscrow.initialize, (admin, address(0), address(registry), MIN_EXPIRY, MAX_EXPIRY)),
            abi.encodeCall(PaymentEscrow.initialize, (admin, address(knd), address(0), MIN_EXPIRY, MAX_EXPIRY))
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.expectRevert(IPaymentEscrow.ZeroAddress.selector);
            new ERC1967Proxy(address(implementation), calls[i]);
        }
    }

    function test_initialize_revertsOnInvalidBounds() public {
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.InvalidExpiryBounds.selector, 0, MAX_EXPIRY));
        new ERC1967Proxy(address(implementation), _initCall(admin, 0, MAX_EXPIRY));
    }

    function test_initialize_revertsWhenCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        escrow.initialize(admin, address(knd), address(registry), MIN_EXPIRY, MAX_EXPIRY);
    }

    function test_implementation_initializersDisabled() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(admin, address(knd), address(registry), MIN_EXPIRY, MAX_EXPIRY);
    }

    // =============================================================
    // lock: None -> Locked
    // =============================================================

    function test_lock_pullsKndAndRecordsIntent() public {
        uint64 expiry = _expiry();
        vm.expectEmit(address(escrow));
        emit IPaymentEscrow.Locked(ID, partnerA, partnerB, AMOUNT, expiry, META);
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, expiry, META);

        IPaymentEscrow.Intent memory intent = escrow.intents(ID);
        assertEq(intent.sender, partnerA);
        assertEq(intent.receiver, partnerB);
        assertEq(intent.amount, AMOUNT);
        assertEq(intent.expiry, expiry);
        assertEq(uint8(intent.status), uint8(IPaymentEscrow.Status.Locked));
        assertEq(intent.metadataHash, META);
        assertEq(knd.balanceOf(address(escrow)), AMOUNT);
        assertEq(knd.balanceOf(partnerA), 100_000e18 - AMOUNT);
    }

    function test_lock_revertsOnReusedId() public {
        _lock(ID);
        vm.prank(partnerA);
        escrow.release(ID);
        // Even after the intent is terminal, its id can never be used again.
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.IntentExists.selector, ID));
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, _expiry(), META);
    }

    function test_lock_revertsOnZeroAmount() public {
        vm.expectRevert(IPaymentEscrow.ZeroAmount.selector);
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, 0, _expiry(), META);
    }

    function test_lock_revertsOnSameParty() public {
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.SameParty.selector, partnerA));
        vm.prank(partnerA);
        escrow.lock(ID, partnerA, AMOUNT, _expiry(), META);
    }

    function test_lock_revertsWhenSenderNotPartner() public {
        _fund(participantOnly, AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, participantOnly));
        vm.prank(participantOnly);
        escrow.lock(ID, partnerB, AMOUNT, _expiry(), META);
    }

    function test_lock_revertsWhenReceiverNotPartner() public {
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, stranger));
        vm.prank(partnerA);
        escrow.lock(ID, stranger, AMOUNT, _expiry(), META);
    }

    function test_lock_revertsWhenReceiverInactive() public {
        vm.prank(admin);
        registry.setAccount(partnerB, IParticipantRegistry.Kind.Partner, 1, false);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, partnerB));
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, _expiry(), META);
    }

    function test_lock_revertsWhenReceiverBlocked() public {
        vm.prank(compliance);
        knd.blockAccount(partnerB);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, partnerB));
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, _expiry(), META);
    }

    function test_lock_revertsWhenSenderBlocked() public {
        vm.prank(compliance);
        knd.blockAccount(partnerA);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, partnerA));
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, _expiry(), META);
    }

    function test_lock_acceptsExpiryAtExactBounds() public {
        uint64 nowTs = uint64(vm.getBlockTimestamp());
        vm.startPrank(partnerA);
        escrow.lock(keccak256("min"), partnerB, AMOUNT, nowTs + MIN_EXPIRY, META);
        escrow.lock(keccak256("max"), partnerB, AMOUNT, nowTs + MAX_EXPIRY, META);
        vm.stopPrank();
        assertEq(knd.balanceOf(address(escrow)), 2 * uint256(AMOUNT));
    }

    function test_lock_revertsOnExpiryTooSoon() public {
        uint64 expiry = uint64(vm.getBlockTimestamp()) + MIN_EXPIRY - 1;
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.BadExpiry.selector, expiry));
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, expiry, META);
    }

    function test_lock_revertsOnExpiryTooLate() public {
        uint64 expiry = uint64(vm.getBlockTimestamp()) + MAX_EXPIRY + 1;
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.BadExpiry.selector, expiry));
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, expiry, META);
    }

    function test_lock_revertsWithoutApproval() public {
        vm.prank(partnerA);
        knd.approve(address(escrow), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(escrow), 0, AMOUNT)
        );
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, _expiry(), META);
    }

    function test_lock_revertsWhenEscrowPaused() public {
        vm.prank(pauser);
        escrow.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, _expiry(), META);
    }

    function test_lock_revertsWhenTokenPaused() public {
        vm.prank(pauser);
        knd.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, _expiry(), META);
    }

    // =============================================================
    // release: Locked -> Released
    // =============================================================

    function test_release_bySender() public {
        _lock(ID);
        vm.expectEmit(address(escrow));
        emit IPaymentEscrow.Released(ID, partnerA);
        vm.prank(partnerA);
        escrow.release(ID);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Released));
        assertEq(knd.balanceOf(partnerB), 100_000e18 + AMOUNT);
        assertEq(knd.balanceOf(address(escrow)), 0);
    }

    function test_release_byReleaser() public {
        _lock(ID);
        vm.expectEmit(address(escrow));
        emit IPaymentEscrow.Released(ID, releaser);
        vm.prank(releaser);
        escrow.release(ID);
        assertEq(knd.balanceOf(partnerB), 100_000e18 + AMOUNT);
    }

    function test_release_revertsForReceiver() public {
        _lock(ID);
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.Unauthorized.selector, partnerB));
        vm.prank(partnerB);
        escrow.release(ID);
    }

    function test_release_revertsForStranger() public {
        _lock(ID);
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.Unauthorized.selector, stranger));
        vm.prank(stranger);
        escrow.release(ID);
    }

    function test_release_revertsForUnknownIntent() public {
        _expectBadStatus(ID, IPaymentEscrow.Status.None);
        vm.prank(releaser);
        escrow.release(ID);
    }

    /// @dev Review C-05: after expiry both release and refund are valid; SCP-04 handles the race off-chain.
    function test_release_stillValidAfterExpiry() public {
        uint64 expiry = _lock(ID);
        vm.warp(expiry + 1);
        vm.prank(releaser);
        escrow.release(ID);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Released));
    }

    /// @dev Review C-12: exit paths don't re-check the registry, so deactivating a partner never traps funds.
    function test_release_paysDeactivatedReceiver() public {
        _lock(ID);
        vm.prank(admin);
        registry.setAccount(partnerB, IParticipantRegistry.Kind.Partner, 1, false);
        vm.prank(releaser);
        escrow.release(ID);
        assertEq(knd.balanceOf(partnerB), 100_000e18 + AMOUNT);
    }

    /// @dev The token blocklist is the only intended trap: a blocked receiver can't be paid until unblocked.
    function test_release_revertsWhileReceiverBlocked() public {
        _lock(ID);
        vm.prank(compliance);
        knd.blockAccount(partnerB);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, partnerB));
        vm.prank(releaser);
        escrow.release(ID);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Locked));
    }

    function test_release_revertsWhenPaused() public {
        _lock(ID);
        vm.prank(pauser);
        escrow.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(releaser);
        escrow.release(ID);
    }

    // =============================================================
    // reject: Locked -> Refunded (by the receiver, now)
    // =============================================================

    function test_reject_byReceiverRefundsSender() public {
        _lock(ID);
        vm.expectEmit(address(escrow));
        emit IPaymentEscrow.Refunded(ID, partnerB);
        vm.prank(partnerB);
        escrow.reject(ID);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Refunded));
        assertEq(knd.balanceOf(partnerA), 100_000e18);
        assertEq(knd.balanceOf(address(escrow)), 0);
    }

    function test_reject_revertsForSender() public {
        _lock(ID);
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.Unauthorized.selector, partnerA));
        vm.prank(partnerA);
        escrow.reject(ID);
    }

    function test_reject_revertsForReleaser() public {
        _lock(ID);
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.Unauthorized.selector, releaser));
        vm.prank(releaser);
        escrow.reject(ID);
    }

    function test_reject_revertsWhenPaused() public {
        _lock(ID);
        vm.prank(pauser);
        escrow.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(partnerB);
        escrow.reject(ID);
    }

    // =============================================================
    // refund: Locked -> Refunded (anyone, at or after expiry)
    // =============================================================

    function test_refund_revertsBeforeExpiry() public {
        uint64 expiry = _lock(ID);
        vm.warp(expiry - 1);
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.NotExpired.selector, ID));
        vm.prank(stranger);
        escrow.refund(ID);
    }

    function test_refund_byAnyoneAtExpiry() public {
        uint64 expiry = _lock(ID);
        vm.warp(expiry);
        vm.expectEmit(address(escrow));
        emit IPaymentEscrow.Refunded(ID, stranger);
        vm.prank(stranger);
        escrow.refund(ID);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Refunded));
        assertEq(knd.balanceOf(partnerA), 100_000e18);
    }

    function test_refund_revertsForUnknownIntent() public {
        _expectBadStatus(ID, IPaymentEscrow.Status.None);
        escrow.refund(ID);
    }

    function test_refund_revertsWhenPaused() public {
        uint64 expiry = _lock(ID);
        vm.warp(expiry);
        vm.prank(pauser);
        escrow.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        escrow.refund(ID);
    }

    function test_refund_worksAfterPauseOutlastsExpiry() public {
        uint64 expiry = _lock(ID);
        vm.prank(pauser);
        escrow.pause();
        vm.warp(expiry + 2 days);
        vm.prank(unpauser);
        escrow.unpause();
        escrow.refund(ID);
        assertEq(knd.balanceOf(partnerA), 100_000e18);
    }

    // =============================================================
    // dispute: Locked -> Disputed (sender or receiver, before expiry)
    // =============================================================

    function test_dispute_bySender() public {
        _lock(ID);
        vm.expectEmit(address(escrow));
        emit IPaymentEscrow.Disputed(ID, partnerA);
        vm.prank(partnerA);
        escrow.dispute(ID);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Disputed));
    }

    function test_dispute_byReceiver() public {
        _lock(ID);
        vm.prank(partnerB);
        escrow.dispute(ID);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Disputed));
    }

    function test_dispute_revertsForStranger() public {
        _lock(ID);
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.Unauthorized.selector, releaser));
        vm.prank(releaser);
        escrow.dispute(ID);
    }

    function test_dispute_lastSecondBeforeExpiry() public {
        uint64 expiry = _lock(ID);
        vm.warp(expiry - 1);
        vm.prank(partnerB);
        escrow.dispute(ID);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Disputed));
    }

    /// @dev At expiry the boundary flips: refund opens and dispute closes, with no gap and no overlap.
    function test_dispute_revertsAtExpiry() public {
        uint64 expiry = _lock(ID);
        vm.warp(expiry);
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.BadExpiry.selector, expiry));
        vm.prank(partnerB);
        escrow.dispute(ID);
    }

    function test_dispute_blocksRefundAndRelease() public {
        uint64 expiry = _lock(ID);
        vm.prank(partnerB);
        escrow.dispute(ID);
        vm.warp(expiry + 1);
        _expectBadStatus(ID, IPaymentEscrow.Status.Disputed);
        escrow.refund(ID);
        _expectBadStatus(ID, IPaymentEscrow.Status.Disputed);
        vm.prank(releaser);
        escrow.release(ID);
        assertEq(knd.balanceOf(address(escrow)), AMOUNT);
    }

    function test_dispute_revertsWhenPaused() public {
        _lock(ID);
        vm.prank(pauser);
        escrow.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(partnerA);
        escrow.dispute(ID);
    }

    // =============================================================
    // resolve: Disputed -> Resolved (arbiter)
    // =============================================================

    function _disputed() internal {
        _lock(ID);
        vm.prank(partnerB);
        escrow.dispute(ID);
    }

    function test_resolve_splitsBetweenParties() public {
        _disputed();
        vm.expectEmit(address(escrow));
        emit IPaymentEscrow.Resolved(ID, 600e18, 400e18);
        vm.prank(arbiter);
        escrow.resolve(ID, 600e18);
        assertEq(uint8(_status(ID)), uint8(IPaymentEscrow.Status.Resolved));
        assertEq(knd.balanceOf(partnerB), 100_000e18 + 600e18);
        assertEq(knd.balanceOf(partnerA), 100_000e18 - AMOUNT + 400e18);
        assertEq(knd.balanceOf(address(escrow)), 0);
    }

    function test_resolve_allToReceiver() public {
        _disputed();
        vm.prank(arbiter);
        escrow.resolve(ID, AMOUNT);
        assertEq(knd.balanceOf(partnerB), 100_000e18 + AMOUNT);
        assertEq(knd.balanceOf(partnerA), 100_000e18 - AMOUNT);
    }

    function test_resolve_allToSender() public {
        _disputed();
        vm.prank(arbiter);
        escrow.resolve(ID, 0);
        assertEq(knd.balanceOf(partnerA), 100_000e18);
        assertEq(knd.balanceOf(partnerB), 100_000e18);
    }

    function test_resolve_revertsOnInvalidSplit() public {
        _disputed();
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.InvalidSplit.selector, AMOUNT + 1, AMOUNT));
        vm.prank(arbiter);
        escrow.resolve(ID, AMOUNT + 1);
    }

    function test_resolve_revertsWithoutArbiterRole() public {
        _disputed();
        _expectMissingRole(releaser, Roles.ARBITER_ROLE);
        vm.prank(releaser);
        escrow.resolve(ID, 0);
    }

    function test_resolve_revertsWhenNotDisputed() public {
        _lock(ID);
        _expectBadStatus(ID, IPaymentEscrow.Status.Locked);
        vm.prank(arbiter);
        escrow.resolve(ID, 0);
    }

    function test_resolve_revertsWhenPaused() public {
        _disputed();
        vm.prank(pauser);
        escrow.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(arbiter);
        escrow.resolve(ID, 0);
    }

    // =============================================================
    // Every action from every status
    // =============================================================

    /// @dev Builds an intent in `status` under `id`.
    function _intentIn(bytes32 id, IPaymentEscrow.Status status) internal {
        if (status == IPaymentEscrow.Status.None) return;
        _lock(id);
        if (status == IPaymentEscrow.Status.Released) {
            vm.prank(partnerA);
            escrow.release(id);
        } else if (status == IPaymentEscrow.Status.Refunded) {
            vm.prank(partnerB);
            escrow.reject(id);
        } else if (status == IPaymentEscrow.Status.Disputed || status == IPaymentEscrow.Status.Resolved) {
            vm.prank(partnerA);
            escrow.dispute(id);
            if (status == IPaymentEscrow.Status.Resolved) {
                vm.prank(arbiter);
                escrow.resolve(id, 0);
            }
        }
    }

    /// @dev Only the transitions in the L1 section 3.4 table succeed; every other action reverts BadStatus.
    function test_matrix_onlyDefinedTransitionsSucceed() public {
        for (uint8 s; s <= uint8(IPaymentEscrow.Status.Resolved); ++s) {
            IPaymentEscrow.Status status = IPaymentEscrow.Status(s);
            if (status == IPaymentEscrow.Status.Locked) continue; // covered by the transition tests above
            bytes32 id = keccak256(abi.encode("matrix", s));
            _intentIn(id, status);

            _expectBadStatus(id, status);
            vm.prank(partnerA);
            escrow.release(id);

            _expectBadStatus(id, status);
            vm.prank(partnerB);
            escrow.reject(id);

            _expectBadStatus(id, status);
            escrow.refund(id);

            _expectBadStatus(id, status);
            vm.prank(partnerA);
            escrow.dispute(id);

            if (status != IPaymentEscrow.Status.Disputed) {
                _expectBadStatus(id, status);
                vm.prank(arbiter);
                escrow.resolve(id, 0);
            }
        }
    }

    // =============================================================
    // Administration
    // =============================================================

    function test_setExpiryBounds_setsAndEmits() public {
        vm.expectEmit(address(escrow));
        emit IPaymentEscrow.ExpiryBoundsSet(1 hours, 2 hours);
        vm.prank(limitsAdmin);
        escrow.setExpiryBounds(1 hours, 2 hours);

        uint64 expiry = uint64(vm.getBlockTimestamp()) + 30 minutes;
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.BadExpiry.selector, expiry));
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, AMOUNT, expiry, META);
    }

    function test_setExpiryBounds_revertsOnZeroMin() public {
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.InvalidExpiryBounds.selector, 0, 1 hours));
        vm.prank(limitsAdmin);
        escrow.setExpiryBounds(0, 1 hours);
    }

    function test_setExpiryBounds_revertsWhenMinAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.InvalidExpiryBounds.selector, 2 hours, 1 hours));
        vm.prank(limitsAdmin);
        escrow.setExpiryBounds(2 hours, 1 hours);
    }

    function test_setExpiryBounds_revertsWithoutLimitsAdminRole() public {
        _expectMissingRole(admin, Roles.LIMITS_ADMIN_ROLE);
        vm.prank(admin);
        escrow.setExpiryBounds(1 hours, 2 hours);
    }

    /// @dev SCP-13: the pause stops intent operations; the timelock can still fix parameters during an incident.
    function test_setExpiryBounds_worksWhilePaused() public {
        vm.prank(pauser);
        escrow.pause();
        vm.prank(limitsAdmin);
        escrow.setExpiryBounds(1 hours, 2 hours);
    }

    function test_pause_roles() public {
        _expectMissingRole(unpauser, Roles.PAUSER_ROLE);
        vm.prank(unpauser);
        escrow.pause();

        vm.expectEmit(address(escrow));
        emit PausableUpgradeable.Paused(pauser);
        vm.prank(pauser);
        escrow.pause();
        assertTrue(escrow.paused());

        _expectMissingRole(pauser, Roles.UNPAUSER_ROLE);
        vm.prank(pauser);
        escrow.unpause();

        vm.expectEmit(address(escrow));
        emit PausableUpgradeable.Unpaused(unpauser);
        vm.prank(unpauser);
        escrow.unpause();
        assertFalse(escrow.paused());
    }

    // =============================================================
    // UUPS upgrade
    // =============================================================

    function test_upgrade_byUpgraderKeepsIntents() public {
        _lock(ID);
        PaymentEscrowV2Mock v2 = new PaymentEscrowV2Mock();
        vm.prank(upgrader);
        escrow.upgradeToAndCall(address(v2), "");
        assertEq(PaymentEscrowV2Mock(address(escrow)).version(), 2);
        assertEq(escrow.intents(ID).amount, AMOUNT);
        vm.prank(releaser);
        escrow.release(ID);
        assertEq(knd.balanceOf(partnerB), 100_000e18 + AMOUNT);
    }

    function test_upgrade_revertsWithoutUpgraderRole() public {
        PaymentEscrowV2Mock v2 = new PaymentEscrowV2Mock();
        _expectMissingRole(admin, Roles.UPGRADER_ROLE);
        vm.prank(admin);
        escrow.upgradeToAndCall(address(v2), "");
    }

    function test_supportsInterface_accessControl() public view {
        assertTrue(escrow.supportsInterface(type(IAccessControl).interfaceId));
    }
}
