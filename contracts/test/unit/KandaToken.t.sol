// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {KandaToken} from "../../src/token/KandaToken.sol";
import {IKandaToken} from "../../src/interfaces/IKandaToken.sol";
import {Roles} from "../../src/governance/Roles.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {KandaTokenV2Mock} from "../mocks/KandaTokenV2Mock.sol";

/// @notice Shared setup for KandaToken unit and fuzz tests: a proxy with every role held by a separate key.
abstract contract KandaTokenTestBase is Test {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 internal constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 internal constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );
    bytes32 internal constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");
    /// @dev keccak256(abi.encode(uint256(keccak256("kanda.storage.KandaToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant KANDA_TOKEN_STORAGE_LOCATION =
        0xedfafc115e36e8673ee7cb02d06638cbb83fab9dd026fdeb53f1d6c738202d00;

    KandaToken internal knd;
    KandaToken internal implementation;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal compliance = makeAddr("compliance");
    address internal upgrader = makeAddr("upgrader");
    address internal stranger = makeAddr("stranger");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    address internal alice;
    uint256 internal alicePk;

    function setUp() public virtual {
        (alice, alicePk) = makeAddrAndKey("alice");

        implementation = new KandaToken();
        knd = KandaToken(
            address(new ERC1967Proxy(address(implementation), abi.encodeCall(KandaToken.initialize, (admin))))
        );

        vm.startPrank(admin);
        knd.grantRole(Roles.MINTER_ROLE, minter);
        knd.grantRole(Roles.PAUSER_ROLE, pauser);
        knd.grantRole(Roles.UNPAUSER_ROLE, unpauser);
        knd.grantRole(Roles.COMPLIANCE_ROLE, compliance);
        knd.grantRole(Roles.UPGRADER_ROLE, upgrader);
        vm.stopPrank();
    }

    // ---- helpers ----

    function _mint(address to, uint256 amount) internal {
        vm.prank(minter);
        knd.mint(to, amount);
    }

    function _block(address account) internal {
        vm.prank(compliance);
        knd.blockAccount(account);
    }

    function _pause() internal {
        vm.prank(pauser);
        knd.pause();
    }

    function _sign(uint256 pk, bytes32 structHash) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        return vm.sign(pk, keccak256(abi.encodePacked("\x19\x01", knd.DOMAIN_SEPARATOR(), structHash)));
    }

    function _signTransferAuth(
        uint256 pk,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8, bytes32, bytes32) {
        return _sign(
            pk,
            keccak256(abi.encode(TRANSFER_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce))
        );
    }

    function _signReceiveAuth(
        uint256 pk,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8, bytes32, bytes32) {
        return _sign(
            pk,
            keccak256(abi.encode(RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce))
        );
    }

    function _signCancel(uint256 pk, address authorizer, bytes32 nonce)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        return _sign(pk, keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce)));
    }

    function _signPermit(uint256 pk, address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        return _sign(pk, keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)));
    }

    function _expectMissingRole(address account, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role));
    }
}

/// @notice Unit tests for KandaToken, L1 section 3.1: every role check, blocked sender, receiver and spender,
///         pause on every path, permit and EIP-3009 replay protection, cancelled authorization.
contract KandaTokenTest is KandaTokenTestBase {
    bytes32 internal constant NONCE = keccak256("nonce-1");

    // =============================================================
    // Initialization and metadata
    // =============================================================

    function test_initialize_setsMetadata() public view {
        assertEq(knd.name(), "Kanda");
        assertEq(knd.symbol(), "KND");
        assertEq(knd.decimals(), 18);
        assertEq(knd.totalSupply(), 0);
        assertFalse(knd.paused());
    }

    function test_initialize_grantsOnlyDefaultAdmin() public {
        KandaToken fresh = KandaToken(
            address(new ERC1967Proxy(address(implementation), abi.encodeCall(KandaToken.initialize, (admin))))
        );
        assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(fresh.hasRole(Roles.MINTER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.PAUSER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.UNPAUSER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.COMPLIANCE_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.UPGRADER_ROLE, admin));
    }

    function test_initialize_revertsOnZeroAdmin() public {
        vm.expectRevert(IKandaToken.ZeroAddress.selector);
        new ERC1967Proxy(address(implementation), abi.encodeCall(KandaToken.initialize, (address(0))));
    }

    function test_initialize_revertsWhenCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        knd.initialize(stranger);
    }

    function test_implementation_initializersDisabled() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(stranger);
    }

    function test_domainSeparator_matchesEip712() public view {
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("Kanda"),
                keccak256("1"),
                block.chainid,
                address(knd)
            )
        );
        assertEq(knd.DOMAIN_SEPARATOR(), expected);
    }

    // =============================================================
    // mint
    // =============================================================

    function test_mint_byMinter() public {
        vm.expectEmit(address(knd));
        emit IERC20.Transfer(address(0), alice, 100e18);
        _mint(alice, 100e18);
        assertEq(knd.balanceOf(alice), 100e18);
        assertEq(knd.totalSupply(), 100e18);
    }

    function test_mint_revertsWithoutMinterRole() public {
        _expectMissingRole(stranger, Roles.MINTER_ROLE);
        vm.prank(stranger);
        knd.mint(alice, 1);
    }

    function test_mint_revertsForAdminWithoutMinterRole() public {
        _expectMissingRole(admin, Roles.MINTER_ROLE);
        vm.prank(admin);
        knd.mint(alice, 1);
    }

    function test_mint_revertsWhenPaused() public {
        _pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _mint(alice, 1);
    }

    function test_mint_revertsToBlockedAccount() public {
        _block(alice);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, alice));
        _mint(alice, 1);
    }

    function test_mint_revertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        _mint(address(0), 1);
    }

    // =============================================================
    // burn
    // =============================================================

    function test_burn_burnsCallerBalance() public {
        _mint(minter, 10e18);
        vm.expectEmit(address(knd));
        emit IERC20.Transfer(minter, address(0), 4e18);
        vm.prank(minter);
        knd.burn(4e18);
        assertEq(knd.balanceOf(minter), 6e18);
        assertEq(knd.totalSupply(), 6e18);
    }

    function test_burn_revertsWithoutMinterRole() public {
        _mint(stranger, 1);
        _expectMissingRole(stranger, Roles.MINTER_ROLE);
        vm.prank(stranger);
        knd.burn(1);
    }

    function test_burn_revertsWhenPaused() public {
        _mint(minter, 1);
        _pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(minter);
        knd.burn(1);
    }

    function test_burn_revertsWhenCallerBlocked() public {
        _mint(minter, 1);
        _block(minter);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, minter));
        vm.prank(minter);
        knd.burn(1);
    }

    function test_burn_revertsOnInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, minter, 0, 1));
        vm.prank(minter);
        knd.burn(1);
    }

    // =============================================================
    // burnFrom
    // =============================================================

    function test_burnFrom_spendsAllowance() public {
        _mint(alice, 10e18);
        vm.prank(alice);
        knd.approve(minter, 6e18);

        vm.prank(minter);
        knd.burnFrom(alice, 4e18);

        assertEq(knd.balanceOf(alice), 6e18);
        assertEq(knd.allowance(alice, minter), 2e18);
        assertEq(knd.totalSupply(), 6e18);
    }

    function test_burnFrom_revertsWithoutMinterRole() public {
        _mint(alice, 1);
        vm.prank(alice);
        knd.approve(stranger, 1);
        _expectMissingRole(stranger, Roles.MINTER_ROLE);
        vm.prank(stranger);
        knd.burnFrom(alice, 1);
    }

    function test_burnFrom_revertsOnInsufficientAllowance() public {
        _mint(alice, 10);
        vm.prank(alice);
        knd.approve(minter, 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, minter, 5, 6));
        vm.prank(minter);
        knd.burnFrom(alice, 6);
    }

    function test_burnFrom_revertsWhenPaused() public {
        _mint(alice, 1);
        vm.prank(alice);
        knd.approve(minter, 1);
        _pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(minter);
        knd.burnFrom(alice, 1);
    }

    function test_burnFrom_revertsWhenFromBlocked() public {
        _mint(alice, 1);
        vm.prank(alice);
        knd.approve(minter, 1);
        _block(alice);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, alice));
        vm.prank(minter);
        knd.burnFrom(alice, 1);
    }

    // =============================================================
    // transfer and transferFrom
    // =============================================================

    function test_transfer_moves() public {
        _mint(alice, 10);
        vm.prank(alice);
        assertTrue(knd.transfer(bob, 4));
        assertEq(knd.balanceOf(alice), 6);
        assertEq(knd.balanceOf(bob), 4);
    }

    function test_transfer_revertsWhenSenderBlocked() public {
        _mint(alice, 10);
        _block(alice);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, alice));
        vm.prank(alice);
        knd.transfer(bob, 1);
    }

    function test_transfer_revertsWhenReceiverBlocked() public {
        _mint(alice, 10);
        _block(bob);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, bob));
        vm.prank(alice);
        knd.transfer(bob, 1);
    }

    function test_transfer_revertsWhenPaused() public {
        _mint(alice, 10);
        _pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(alice);
        knd.transfer(bob, 1);
    }

    function test_transferFrom_moves() public {
        _mint(alice, 10);
        vm.prank(alice);
        knd.approve(carol, 5);
        vm.prank(carol);
        assertTrue(knd.transferFrom(alice, bob, 5));
        assertEq(knd.balanceOf(bob), 5);
        assertEq(knd.allowance(alice, carol), 0);
    }

    function test_transferFrom_revertsWhenSpenderBlocked() public {
        _mint(alice, 10);
        vm.prank(alice);
        knd.approve(carol, 5);
        _block(carol);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, carol));
        vm.prank(carol);
        knd.transferFrom(alice, bob, 5);
    }

    function test_transferFrom_revertsWhenFromBlocked() public {
        _mint(alice, 10);
        vm.prank(alice);
        knd.approve(carol, 5);
        _block(alice);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, alice));
        vm.prank(carol);
        knd.transferFrom(alice, bob, 5);
    }

    function test_transferFrom_revertsWhenToBlocked() public {
        _mint(alice, 10);
        vm.prank(alice);
        knd.approve(carol, 5);
        _block(bob);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, bob));
        vm.prank(carol);
        knd.transferFrom(alice, bob, 5);
    }

    function test_transferFrom_revertsWhenPaused() public {
        _mint(alice, 10);
        vm.prank(alice);
        knd.approve(carol, 5);
        _pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(carol);
        knd.transferFrom(alice, bob, 5);
    }

    // =============================================================
    // Blocklist
    // =============================================================

    function test_blockAccount_blocksAndEmits() public {
        vm.expectEmit(address(knd));
        emit IKandaToken.Blocked(alice);
        _block(alice);
        assertTrue(knd.isBlocked(alice));
    }

    function test_blockAccount_revertsWithoutComplianceRole() public {
        _expectMissingRole(stranger, Roles.COMPLIANCE_ROLE);
        vm.prank(stranger);
        knd.blockAccount(alice);
    }

    function test_blockAccount_revertsForAdminWithoutComplianceRole() public {
        _expectMissingRole(admin, Roles.COMPLIANCE_ROLE);
        vm.prank(admin);
        knd.blockAccount(alice);
    }

    /// @dev Blocking the zero address would stop every mint and burn, so it is refused.
    function test_blockAccount_revertsOnZeroAddress() public {
        vm.expectRevert(IKandaToken.ZeroAddress.selector);
        vm.prank(compliance);
        knd.blockAccount(address(0));
    }

    function test_unblockAccount_unblocksAndEmits() public {
        _mint(alice, 10);
        _block(alice);
        vm.expectEmit(address(knd));
        emit IKandaToken.Unblocked(alice);
        vm.prank(compliance);
        knd.unblockAccount(alice);
        assertFalse(knd.isBlocked(alice));

        vm.prank(alice);
        knd.transfer(bob, 10);
        assertEq(knd.balanceOf(bob), 10);
    }

    function test_unblockAccount_revertsWithoutComplianceRole() public {
        _block(alice);
        _expectMissingRole(stranger, Roles.COMPLIANCE_ROLE);
        vm.prank(stranger);
        knd.unblockAccount(alice);
    }

    function test_blocked_keepsBalanceFrozen() public {
        _mint(alice, 10);
        _block(alice);
        assertEq(knd.balanceOf(alice), 10);
    }

    function test_blocked_canStillBeApprovedButNotSpentFrom() public {
        _mint(alice, 10);
        vm.prank(alice);
        knd.approve(carol, 10);
        _block(alice);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, alice));
        vm.prank(carol);
        knd.transferFrom(alice, carol, 10);
    }

    /// @dev ERC-7201: the blocked flag lives at mapping slot keccak256(account . location).
    function test_storage_blocklistAtNamespacedSlot() public {
        _block(alice);
        bytes32 slot = keccak256(abi.encode(alice, KANDA_TOKEN_STORAGE_LOCATION));
        assertEq(uint256(vm.load(address(knd), slot)), 1);
    }

    // =============================================================
    // Pause
    // =============================================================

    function test_pause_byPauser() public {
        vm.expectEmit(address(knd));
        emit PausableUpgradeable.Paused(pauser);
        _pause();
        assertTrue(knd.paused());
    }

    function test_pause_revertsWithoutPauserRole() public {
        _expectMissingRole(unpauser, Roles.PAUSER_ROLE);
        vm.prank(unpauser);
        knd.pause();
    }

    function test_pause_revertsWhenAlreadyPaused() public {
        _pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(pauser);
        knd.pause();
    }

    function test_unpause_byUnpauser() public {
        _pause();
        vm.expectEmit(address(knd));
        emit PausableUpgradeable.Unpaused(unpauser);
        vm.prank(unpauser);
        knd.unpause();
        assertFalse(knd.paused());
    }

    function test_unpause_revertsWithoutUnpauserRole() public {
        _pause();
        _expectMissingRole(pauser, Roles.UNPAUSER_ROLE);
        vm.prank(pauser);
        knd.unpause();
    }

    function test_unpause_revertsWhenNotPaused() public {
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        vm.prank(unpauser);
        knd.unpause();
    }

    function test_pause_approveStillWorks() public {
        _pause();
        vm.prank(alice);
        knd.approve(bob, 1);
        assertEq(knd.allowance(alice, bob), 1);
    }

    // =============================================================
    // rescueERC20
    // =============================================================

    function test_rescueERC20_returnsToken() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(address(knd), 500e6);

        vm.expectEmit(address(knd));
        emit IKandaToken.Rescued(address(usdc), bob, 200e6);
        vm.prank(admin);
        knd.rescueERC20(address(usdc), bob, 200e6);

        assertEq(usdc.balanceOf(bob), 200e6);
        assertEq(usdc.balanceOf(address(knd)), 300e6);
    }

    function test_rescueERC20_revertsWithoutAdminRole() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        _expectMissingRole(stranger, knd.DEFAULT_ADMIN_ROLE());
        vm.prank(stranger);
        knd.rescueERC20(address(usdc), bob, 1);
    }

    function test_rescueERC20_revertsForKnd() public {
        _mint(address(knd), 1);
        vm.expectRevert(IKandaToken.CannotRescueKnd.selector);
        vm.prank(admin);
        knd.rescueERC20(address(knd), bob, 1);
    }

    function test_rescueERC20_revertsOnZeroRecipient() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        vm.expectRevert(IKandaToken.ZeroAddress.selector);
        vm.prank(admin);
        knd.rescueERC20(address(usdc), address(0), 1);
    }

    // =============================================================
    // Permit (EIP-2612)
    // =============================================================

    function test_permit_setsAllowance() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, alice, bob, 50, 0, deadline);
        knd.permit(alice, bob, 50, deadline, v, r, s);
        assertEq(knd.allowance(alice, bob), 50);
        assertEq(knd.nonces(alice), 1);
    }

    function test_permit_revertsOnReplay() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, alice, bob, 50, 0, deadline);
        knd.permit(alice, bob, 50, deadline, v, r, s);

        // The same signature now recovers against nonce 1, so it resolves to some other signer.
        vm.expectPartialRevert(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector);
        knd.permit(alice, bob, 50, deadline, v, r, s);
    }

    function test_permit_revertsWhenExpired() public {
        uint256 deadline = vm.getBlockTimestamp() + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, alice, bob, 50, 0, deadline);
        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, deadline));
        knd.permit(alice, bob, 50, deadline, v, r, s);
    }

    function test_permit_revertsOnOtherChain() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(alicePk, alice, bob, 50, 0, deadline);
        vm.chainId(block.chainid + 1);
        vm.expectPartialRevert(ERC20PermitUpgradeable.ERC2612InvalidSigner.selector);
        knd.permit(alice, bob, 50, deadline, v, r, s);
    }

    // =============================================================
    // transferWithAuthorization (EIP-3009)
    // =============================================================

    function test_transferWithAuthorization_moves() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);

        vm.expectEmit(address(knd));
        emit IKandaToken.AuthorizationUsed(alice, NONCE);
        vm.expectEmit(address(knd));
        emit IERC20.Transfer(alice, bob, 40);
        vm.prank(stranger);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);

        assertEq(knd.balanceOf(bob), 40);
        assertTrue(knd.authorizationState(alice, NONCE));
    }

    function test_transferWithAuthorization_revertsOnReplay() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AuthorizationUsedOrCanceled.selector, alice, NONCE));
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
        assertEq(knd.balanceOf(bob), 40);
    }

    function test_transferWithAuthorization_revertsBeforeValidAfter() public {
        _mint(alice, 100);
        uint256 validAfter = vm.getBlockTimestamp();
        uint256 validBefore = vm.getBlockTimestamp() + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, validAfter, validBefore, NONCE);

        // validAfter is exclusive: the authorization is valid only once block.timestamp > validAfter.
        vm.expectRevert(IKandaToken.AuthorizationNotYetValid.selector);
        knd.transferWithAuthorization(alice, bob, 40, validAfter, validBefore, NONCE, v, r, s);

        vm.warp(validAfter + 1);
        knd.transferWithAuthorization(alice, bob, 40, validAfter, validBefore, NONCE, v, r, s);
        assertEq(knd.balanceOf(bob), 40);
    }

    function test_transferWithAuthorization_revertsAtValidBefore() public {
        _mint(alice, 100);
        uint256 validBefore = vm.getBlockTimestamp() + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);

        vm.warp(validBefore);
        vm.expectRevert(IKandaToken.AuthorizationExpired.selector);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_transferWithAuthorization_revertsOnWrongSigner() public {
        _mint(alice, 100);
        (, uint256 otherPk) = makeAddrAndKey("mallory");
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(otherPk, alice, bob, 40, 0, validBefore, NONCE);

        vm.expectRevert(IKandaToken.InvalidSignature.selector);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_transferWithAuthorization_revertsOnTamperedValue() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);

        vm.expectRevert(IKandaToken.InvalidSignature.selector);
        knd.transferWithAuthorization(alice, bob, 41, 0, validBefore, NONCE, v, r, s);
    }

    function test_transferWithAuthorization_revertsOnMalformedSignature() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        vm.expectRevert(IKandaToken.InvalidSignature.selector);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, 27, bytes32(0), bytes32(0));
    }

    function test_transferWithAuthorization_revertsOnReceiveSignature() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signReceiveAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);

        vm.expectRevert(IKandaToken.InvalidSignature.selector);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_transferWithAuthorization_revertsOnOtherChain() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);

        vm.chainId(block.chainid + 1);
        vm.expectRevert(IKandaToken.InvalidSignature.selector);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_transferWithAuthorization_revertsWhenPaused() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        _pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
        assertFalse(knd.authorizationState(alice, NONCE));
    }

    function test_transferWithAuthorization_revertsWhenFromBlocked() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        _block(alice);

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, alice));
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_transferWithAuthorization_revertsWhenToBlocked() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        _block(bob);

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, bob));
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    // =============================================================
    // receiveWithAuthorization (EIP-3009)
    // =============================================================

    function test_receiveWithAuthorization_byPayee() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signReceiveAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);

        vm.expectEmit(address(knd));
        emit IKandaToken.AuthorizationUsed(alice, NONCE);
        vm.prank(bob);
        knd.receiveWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);

        assertEq(knd.balanceOf(bob), 40);
        assertTrue(knd.authorizationState(alice, NONCE));
    }

    function test_receiveWithAuthorization_revertsWhenCallerNotPayee() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signReceiveAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.CallerMustBePayee.selector, stranger, bob));
        vm.prank(stranger);
        knd.receiveWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_receiveWithAuthorization_revertsOnReplay() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signReceiveAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        vm.prank(bob);
        knd.receiveWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AuthorizationUsedOrCanceled.selector, alice, NONCE));
        vm.prank(bob);
        knd.receiveWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_receiveWithAuthorization_revertsOnTransferSignature() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);

        vm.expectRevert(IKandaToken.InvalidSignature.selector);
        vm.prank(bob);
        knd.receiveWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_receiveWithAuthorization_revertsWhenExpired() public {
        _mint(alice, 100);
        uint256 validBefore = vm.getBlockTimestamp() + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signReceiveAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        vm.warp(validBefore);

        vm.expectRevert(IKandaToken.AuthorizationExpired.selector);
        vm.prank(bob);
        knd.receiveWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_receiveWithAuthorization_revertsWhenPaused() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signReceiveAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        _pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(bob);
        knd.receiveWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    function test_receiveWithAuthorization_revertsWhenPayeeBlocked() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signReceiveAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        _block(bob);

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, bob));
        vm.prank(bob);
        knd.receiveWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, v, r, s);
    }

    // =============================================================
    // cancelAuthorization (EIP-3009)
    // =============================================================

    function test_cancelAuthorization_preventsUse() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 tv, bytes32 tr, bytes32 ts) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        (uint8 cv, bytes32 cr, bytes32 cs) = _signCancel(alicePk, alice, NONCE);

        vm.expectEmit(address(knd));
        emit IKandaToken.AuthorizationCanceled(alice, NONCE);
        vm.prank(stranger);
        knd.cancelAuthorization(alice, NONCE, cv, cr, cs);
        assertTrue(knd.authorizationState(alice, NONCE));

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AuthorizationUsedOrCanceled.selector, alice, NONCE));
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, tv, tr, ts);
        assertEq(knd.balanceOf(bob), 0);
    }

    function test_cancelAuthorization_revertsWhenAlreadyCanceled() public {
        (uint8 v, bytes32 r, bytes32 s) = _signCancel(alicePk, alice, NONCE);
        knd.cancelAuthorization(alice, NONCE, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AuthorizationUsedOrCanceled.selector, alice, NONCE));
        knd.cancelAuthorization(alice, NONCE, v, r, s);
    }

    function test_cancelAuthorization_revertsWhenAlreadyUsed() public {
        _mint(alice, 100);
        uint256 validBefore = block.timestamp + 1 hours;
        (uint8 tv, bytes32 tr, bytes32 ts) = _signTransferAuth(alicePk, alice, bob, 40, 0, validBefore, NONCE);
        knd.transferWithAuthorization(alice, bob, 40, 0, validBefore, NONCE, tv, tr, ts);

        (uint8 v, bytes32 r, bytes32 s) = _signCancel(alicePk, alice, NONCE);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AuthorizationUsedOrCanceled.selector, alice, NONCE));
        knd.cancelAuthorization(alice, NONCE, v, r, s);
    }

    function test_cancelAuthorization_revertsOnWrongSigner() public {
        (, uint256 otherPk) = makeAddrAndKey("mallory");
        (uint8 v, bytes32 r, bytes32 s) = _signCancel(otherPk, alice, NONCE);

        vm.expectRevert(IKandaToken.InvalidSignature.selector);
        knd.cancelAuthorization(alice, NONCE, v, r, s);
        assertFalse(knd.authorizationState(alice, NONCE));
    }

    function test_cancelAuthorization_revertsOnOtherChain() public {
        (uint8 v, bytes32 r, bytes32 s) = _signCancel(alicePk, alice, NONCE);
        vm.chainId(block.chainid + 1);
        vm.expectRevert(IKandaToken.InvalidSignature.selector);
        knd.cancelAuthorization(alice, NONCE, v, r, s);
    }

    function test_authorizationState_isPerAuthorizer() public {
        (uint8 v, bytes32 r, bytes32 s) = _signCancel(alicePk, alice, NONCE);
        knd.cancelAuthorization(alice, NONCE, v, r, s);
        assertTrue(knd.authorizationState(alice, NONCE));
        assertFalse(knd.authorizationState(bob, NONCE));
    }

    // =============================================================
    // UUPS upgrade
    // =============================================================

    function test_upgrade_byUpgraderKeepsState() public {
        _mint(alice, 100);
        _block(bob);
        KandaTokenV2Mock v2 = new KandaTokenV2Mock();

        vm.prank(upgrader);
        knd.upgradeToAndCall(address(v2), "");

        assertEq(KandaTokenV2Mock(address(knd)).version(), 2);
        assertEq(knd.balanceOf(alice), 100);
        assertTrue(knd.isBlocked(bob));
        assertTrue(knd.hasRole(Roles.MINTER_ROLE, minter));
        assertEq(knd.name(), "Kanda");
    }

    function test_upgrade_revertsWithoutUpgraderRole() public {
        KandaTokenV2Mock v2 = new KandaTokenV2Mock();
        _expectMissingRole(admin, Roles.UPGRADER_ROLE);
        vm.prank(admin);
        knd.upgradeToAndCall(address(v2), "");
    }

    // =============================================================
    // Interfaces
    // =============================================================

    function test_supportsInterface_accessControl() public view {
        assertTrue(knd.supportsInterface(type(IAccessControl).interfaceId));
    }
}
