// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IParticipantRegistry} from "../../src/interfaces/IParticipantRegistry.sol";
import {Roles} from "../../src/governance/Roles.sol";
import {BasketVaultTestBase} from "../unit/BasketVault.t.sol";
import {KandaHandler} from "./handlers/KandaHandler.sol";

/// @notice P0 invariant suite (L1 section 5; ADD section 4): INV-1, INV-2, INV-3, INV-6, INV-7 and INV-8 over random
///         sequences of vault, token, pause, blocklist, time and gold-issuer actions. INV-4 and INV-5 (escrow) are
///         added with PaymentEscrow in P1.
/// @dev PR runs: 256 runs at depth 100. Nightly: FOUNDRY_PROFILE=ci, 10,000 runs at depth 100 (P0 exit gate).
contract KandaInvariants is BasketVaultTestBase {
    /// @dev Lower than the P1 cap so random sequences actually reach it and exercise INV-2.
    uint256 internal constant INVARIANT_CAP = 60_000e18;

    KandaHandler internal handler;
    address internal ap2 = makeAddr("participant2");
    address internal ap3 = makeAddr("participant3");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        registry.setAccount(ap2, IParticipantRegistry.Kind.Participant, 1, true);
        registry.setAccount(ap3, IParticipantRegistry.Kind.Both, 1, true);
        vm.stopPrank();
        _fund(ap2);
        _fund(ap3);
        _fund(holder);
        _fund(stranger);
        _fund(partner);

        vm.prank(limitsAdmin);
        vault.setSupplyCap(INVARIANT_CAP);

        address[] memory participants = new address[](3);
        participants[0] = ap;
        participants[1] = ap2;
        participants[2] = ap3;
        address[] memory holders = new address[](3);
        holders[0] = holder;
        holders[1] = stranger;
        holders[2] = partner; // registered, but as a partner only: vault calls must fail NotActive

        // The base setup grants the vault's unpauser; the token's is needed here too.
        vm.prank(admin);
        knd.grantRole(Roles.UNPAUSER_ROLE, unpauser);

        handler = new KandaHandler(
            knd, registry, vault, gold, participants, holders, pauser, unpauser, compliance, TIER1_LIMIT
        );

        // Weights: create x4, redeem x3, restore x3; every other action once. Disruptions switch on one call in
        // eight and restore clears them, so runs mix long live stretches with pauses, blocks and issuer actions.
        bytes4[] memory selectors = new bytes4[](20);
        selectors[0] = KandaHandler.create.selector;
        selectors[1] = KandaHandler.create.selector;
        selectors[2] = KandaHandler.create.selector;
        selectors[3] = KandaHandler.create.selector;
        selectors[4] = KandaHandler.redeem.selector;
        selectors[5] = KandaHandler.redeem.selector;
        selectors[6] = KandaHandler.redeem.selector;
        selectors[7] = KandaHandler.restore.selector;
        selectors[8] = KandaHandler.restore.selector;
        selectors[9] = KandaHandler.restore.selector;
        selectors[10] = KandaHandler.transfer.selector;
        selectors[11] = KandaHandler.transferFrom.selector;
        selectors[12] = KandaHandler.setTokenPaused.selector;
        selectors[13] = KandaHandler.setVaultPaused.selector;
        selectors[14] = KandaHandler.setCreatePaused.selector;
        selectors[15] = KandaHandler.setBlocked.selector;
        selectors[16] = KandaHandler.warp.selector;
        selectors[17] = KandaHandler.setGoldTransferFee.selector;
        selectors[18] = KandaHandler.setGoldPaused.selector;
        selectors[19] = KandaHandler.setVaultBlacklistedOnGold.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice INV-1 Full backing: for every leg, balanceOf(vault) >= ceil(totalSupply * qtyPerUnit / 1e18).
    function invariant_INV1_fullBacking() public view {
        _assertBacked();
    }

    /// @notice INV-2 totalSupply is at or below the supply cap.
    function invariant_INV2_supplyCap() public view {
        assertLe(knd.totalSupply(), INVARIANT_CAP, "INV-2");
    }

    /// @notice INV-3 Supply changes only inside vault create and redeem.
    function invariant_INV3_supplyOnlyViaVault() public view {
        assertFalse(handler.supplyChangedOutsideVault(), "INV-3: supply moved outside the vault");
        assertEq(knd.totalSupply(), handler.ghostSupply(), "INV-3: supply != ghost");
    }

    /// @notice INV-6 No participant exceeds its daily create or redeem limit.
    function invariant_INV6_dailyLimits() public view {
        assertFalse(handler.dailyLimitExceeded(), "INV-6");
    }

    /// @notice INV-7 Calls blocked by a pause (token, vault, vault creation) never succeed, so never move balances.
    function invariant_INV7_pausesHold() public view {
        assertFalse(handler.pausedCallSucceeded(), "INV-7");
    }

    /// @notice INV-8 A blocked address's KND balance never changes.
    function invariant_INV8_blockedBalancesFrozen() public view {
        assertFalse(handler.blockedBalanceChanged(), "INV-8");
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address account = handler.actorAt(i);
            if (handler.ghostBlocked(account)) {
                assertTrue(knd.isBlocked(account), "INV-8: ghost out of sync");
                assertEq(knd.balanceOf(account), handler.ghostBlockedBalance(account), "INV-8");
            }
        }
    }
}
