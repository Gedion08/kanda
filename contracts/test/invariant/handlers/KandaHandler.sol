// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {KandaToken} from "../../../src/token/KandaToken.sol";
import {ParticipantRegistry} from "../../../src/registry/ParticipantRegistry.sol";
import {BasketVault} from "../../../src/vault/BasketVault.sol";
import {MockGoldToken} from "../../mocks/MockGoldToken.sol";

/// @notice Invariant handler for the P0 contracts (L1 section 5): create, redeem, transfer, transferFrom, pause and
///         unpause on the token and the vault, pauseCreate and unpauseCreate, block and unblock, time warps, and
///         fee-on-transfer, pause and blacklist toggles on the DGLD-like gold token. Escrow actions arrive with
///         PaymentEscrow in P1.
/// @dev fail_on_revert is off, so an assert inside a handler would be swallowed with its revert. Violations are
///      recorded in ghost flags instead, and the invariant contract asserts on them.
contract KandaHandler is Test {
    KandaToken internal immutable knd;
    ParticipantRegistry internal immutable registry;
    BasketVault internal immutable vault;
    MockGoldToken internal immutable gold;
    address internal immutable pauser;
    address internal immutable unpauser;
    address internal immutable compliance;
    uint256 internal immutable tierLimit;

    /// @dev Participants first, then plain holders. Every actor holds basket assets and has approved the vault.
    address[] internal actors;
    uint256 internal immutable participantCount;

    // ---- ghosts ----

    /// @notice KND supply as changed by successful vault calls only (INV-3).
    uint256 public ghostSupply;
    /// @notice Set if totalSupply changed during a call that is not a vault create or redeem (INV-3).
    bool public supplyChangedOutsideVault;
    /// @notice Set if a create or redeem took an account past its tier's daily limit (INV-6).
    bool public dailyLimitExceeded;
    /// @notice Set if a call that a pause should block succeeded (INV-7).
    bool public pausedCallSucceeded;
    /// @notice Set if a blocked account's balance changed (INV-8).
    bool public blockedBalanceChanged;

    mapping(address account => mapping(uint256 day => uint256)) public ghostCreated;
    mapping(address account => mapping(uint256 day => uint256)) public ghostRedeemed;
    mapping(address account => bool) public ghostBlocked;
    mapping(address account => uint256) public ghostBlockedBalance;

    /// @notice Successful calls per action, for the run summary.
    mapping(bytes32 action => uint256) public calls;

    constructor(
        KandaToken knd_,
        ParticipantRegistry registry_,
        BasketVault vault_,
        MockGoldToken gold_,
        address[] memory participants,
        address[] memory holders,
        address pauser_,
        address unpauser_,
        address compliance_,
        uint256 tierLimit_
    ) {
        knd = knd_;
        registry = registry_;
        vault = vault_;
        gold = gold_;
        pauser = pauser_;
        unpauser = unpauser_;
        compliance = compliance_;
        tierLimit = tierLimit_;
        participantCount = participants.length;
        for (uint256 i; i < participants.length; ++i) {
            actors.push(participants[i]);
        }
        for (uint256 i; i < holders.length; ++i) {
            actors.push(holders[i]);
        }
        ghostSupply = knd_.totalSupply();
    }

    // =============================================================
    // Wrapping: INV-3 and INV-8 checks around every action
    // =============================================================

    /// @dev Checks that non-vault actions leave supply unchanged and blocked balances frozen.
    modifier checked(bool isVaultCall) {
        uint256 supplyBefore = knd.totalSupply();
        _;
        if (!isVaultCall && knd.totalSupply() != supplyBefore) supplyChangedOutsideVault = true;
        _checkBlockedBalances();
    }

    // =============================================================
    // Vault
    // =============================================================

    function create(uint256 actorSeed, uint256 toSeed, uint256 amount) external checked(true) {
        address participant = _participantOrAnyone(actorSeed);
        // Half the time to self, so participants hold KND to redeem later.
        address to = toSeed % 2 == 0 ? participant : _actor(toSeed / 2);
        // Mostly well inside the daily limit; one call in ten can go past it to exercise LimitExceeded.
        amount = amount % 10 == 0 ? bound(amount, 1, tierLimit + tierLimit / 5) : bound(amount, 1, tierLimit / 8);
        bool blockedByPause = knd.paused() || vault.paused() || vault.createPaused();
        uint256 supplyBefore = knd.totalSupply();

        vm.prank(participant);
        try vault.createInKind(amount, 0, to) {
            uint256 gross = knd.totalSupply() - supplyBefore;
            ghostSupply += gross;
            uint256 day = block.timestamp / 1 days;
            ghostCreated[participant][day] += gross;
            if (ghostCreated[participant][day] > tierLimit) dailyLimitExceeded = true;
            if (blockedByPause) pausedCallSucceeded = true;
            ++calls["create"];
        } catch {}
    }

    function redeem(uint256 actorSeed, uint256 toSeed, uint256 amount) external checked(true) {
        address participant = _participantOrAnyone(actorSeed);
        address to = _actor(toSeed);
        uint256 balance = knd.balanceOf(participant);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);
        // A creation pause does not block redeem (ADR-011).
        bool blockedByPause = knd.paused() || vault.paused();
        uint256 supplyBefore = knd.totalSupply();

        vm.prank(participant);
        try vault.redeemInKind(amount, new uint256[](2), to) {
            ghostSupply -= supplyBefore - knd.totalSupply();
            uint256 day = block.timestamp / 1 days;
            ghostRedeemed[participant][day] += amount;
            if (ghostRedeemed[participant][day] > tierLimit) dailyLimitExceeded = true;
            if (blockedByPause) pausedCallSucceeded = true;
            ++calls["redeem"];
        } catch {}
    }

    // =============================================================
    // Token
    // =============================================================

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external checked(false) {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, knd.balanceOf(from));
        bool blockedByPause = knd.paused();

        vm.prank(from);
        try knd.transfer(to, amount) {
            if (blockedByPause) pausedCallSucceeded = true;
            ++calls["transfer"];
        } catch {}
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount)
        external
        checked(false)
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, knd.balanceOf(from));
        bool blockedByPause = knd.paused();

        // approve works while paused and while blocked; only balance moves stop.
        vm.prank(from);
        knd.approve(spender, amount);
        vm.prank(spender);
        try knd.transferFrom(from, to, amount) {
            if (blockedByPause) pausedCallSucceeded = true;
            ++calls["transferFrom"];
        } catch {}
    }

    // =============================================================
    // Pauses
    // =============================================================

    function setTokenPaused(uint256 seed) external checked(false) {
        bool paused = _rarelyOn(seed);
        if (paused == knd.paused()) return;
        vm.prank(paused ? pauser : unpauser);
        if (paused) knd.pause();
        else knd.unpause();
        ++calls["tokenPause"];
    }

    function setVaultPaused(uint256 seed) external checked(false) {
        bool paused = _rarelyOn(seed);
        if (paused == vault.paused()) return;
        vm.prank(paused ? pauser : unpauser);
        if (paused) vault.pause();
        else vault.unpause();
        ++calls["vaultPause"];
    }

    function setCreatePaused(uint256 seed) external checked(false) {
        bool paused = _rarelyOn(seed);
        vm.prank(paused ? pauser : unpauser);
        if (paused) vault.pauseCreate();
        else vault.unpauseCreate();
        ++calls["createPause"];
    }

    // =============================================================
    // Blocklist
    // =============================================================

    function setBlocked(uint256 actorSeed, uint256 seed) external checked(false) {
        address account = _actor(actorSeed);
        bool blocked = _rarelyOn(seed);
        vm.prank(compliance);
        if (blocked) knd.blockAccount(account);
        else knd.unblockAccount(account);
        ghostBlocked[account] = blocked;
        ghostBlockedBalance[account] = knd.balanceOf(account);
        ++calls["block"];
    }

    // =============================================================
    // Environment
    // =============================================================

    function warp(uint256 secondsForward) external checked(false) {
        vm.warp(block.timestamp + bound(secondsForward, 1, 1 days));
        ++calls["warp"];
    }

    function setGoldTransferFee(uint16 feeBps) external checked(false) {
        gold.setTransferFeeBps(uint16(bound(feeBps, 0, 300)));
        ++calls["goldFee"];
    }

    function setGoldPaused(uint256 seed) external checked(false) {
        gold.setPaused(_rarelyOn(seed));
        ++calls["goldPause"];
    }

    function setVaultBlacklistedOnGold(uint256 seed) external checked(false) {
        gold.setBlacklisted(address(vault), _rarelyOn(seed));
        ++calls["goldBlacklist"];
    }

    /// @notice Clears every disruption: pauses off, all actors unblocked, gold token live. Weighted so runs spend
    ///         long stretches with the system live, which lets supply, caps and daily limits build up.
    function restore() external checked(false) {
        if (knd.paused()) {
            vm.prank(unpauser);
            knd.unpause();
        }
        if (vault.paused()) {
            vm.prank(unpauser);
            vault.unpause();
        }
        if (vault.createPaused()) {
            vm.prank(unpauser);
            vault.unpauseCreate();
        }
        for (uint256 i; i < actors.length; ++i) {
            if (ghostBlocked[actors[i]]) {
                vm.prank(compliance);
                knd.unblockAccount(actors[i]);
                ghostBlocked[actors[i]] = false;
            }
        }
        gold.setPaused(false);
        gold.setBlacklisted(address(vault), false);
        ++calls["restore"];
    }

    // =============================================================
    // Views for the invariant contract
    // =============================================================

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    // =============================================================
    // Internal
    // =============================================================

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Mostly participants, sometimes a plain holder, so the NotActive path is exercised too.
    function _participantOrAnyone(uint256 seed) internal view returns (address) {
        return seed % 5 == 0 ? _actor(seed / 5) : actors[seed % participantCount];
    }

    /// @dev One call in eight switches a disruption on; the rest switch it off. Pauses, blocks and issuer actions
    ///      still happen in every run, but the system is live most of the time, so creates and redeems succeed.
    function _rarelyOn(uint256 seed) internal pure returns (bool) {
        return seed % 8 == 0;
    }

    function _checkBlockedBalances() internal {
        for (uint256 i; i < actors.length; ++i) {
            address account = actors[i];
            if (ghostBlocked[account] && knd.balanceOf(account) != ghostBlockedBalance[account]) {
                blockedBalanceChanged = true;
            }
        }
    }
}
