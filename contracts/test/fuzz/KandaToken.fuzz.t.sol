// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IKandaToken} from "../../src/interfaces/IKandaToken.sol";
import {KandaTokenTestBase} from "../unit/KandaToken.t.sol";

/// @notice Fuzz tests for KandaToken amount edges, the blocklist and the EIP-3009 validity window (L1 section 6).
contract KandaTokenFuzzTest is KandaTokenTestBase {
    function testFuzz_mintBurn_conservesSupply(uint256 minted, uint256 burned) public {
        minted = bound(minted, 0, type(uint128).max);
        burned = bound(burned, 0, minted);
        _mint(minter, minted);
        vm.prank(minter);
        knd.burn(burned);
        assertEq(knd.totalSupply(), minted - burned);
        assertEq(knd.balanceOf(minter), minted - burned);
    }

    function testFuzz_transfer_blockedEitherSideReverts(uint256 amount, bool blockSender) public {
        amount = bound(amount, 1, type(uint128).max);
        _mint(alice, amount);
        address blocked = blockSender ? alice : bob;
        _block(blocked);

        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, blocked));
        vm.prank(alice);
        knd.transfer(bob, amount);
        assertEq(knd.balanceOf(alice), amount);
        assertEq(knd.balanceOf(bob), 0);
    }

    function testFuzz_transferWithAuthorization_window(
        uint256 value,
        uint64 validAfter,
        uint64 validBefore,
        uint64 at,
        bytes32 nonce
    ) public {
        value = bound(value, 0, type(uint128).max);
        _mint(alice, value);
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuth(alicePk, alice, bob, value, validAfter, validBefore, nonce);
        vm.warp(at);

        if (at <= validAfter) {
            vm.expectRevert(IKandaToken.AuthorizationNotYetValid.selector);
        } else if (at >= validBefore) {
            vm.expectRevert(IKandaToken.AuthorizationExpired.selector);
        }
        knd.transferWithAuthorization(alice, bob, value, validAfter, validBefore, nonce, v, r, s);

        bool ok = at > validAfter && at < validBefore;
        assertEq(knd.authorizationState(alice, nonce), ok);
        assertEq(knd.balanceOf(bob), ok ? value : 0);
    }
}
