// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPaymentEscrow} from "../../src/interfaces/IPaymentEscrow.sol";
import {PaymentEscrowTestBase} from "../unit/PaymentEscrow.t.sol";

/// @notice Fuzz tests for PaymentEscrow: KND is conserved through every exit, and the expiry window is exact.
contract PaymentEscrowFuzzTest is PaymentEscrowTestBase {
    function testFuzz_resolve_conservesKnd(uint128 amount, uint128 toReceiver) public {
        amount = uint128(bound(amount, 1, 100_000e18));
        toReceiver = uint128(bound(toReceiver, 0, amount));
        uint256 totalBefore = knd.balanceOf(partnerA) + knd.balanceOf(partnerB);

        vm.prank(partnerA);
        escrow.lock(ID, partnerB, amount, _expiry(), META);
        vm.prank(partnerB);
        escrow.dispute(ID);
        vm.prank(arbiter);
        escrow.resolve(ID, toReceiver);

        assertEq(knd.balanceOf(address(escrow)), 0);
        assertEq(knd.balanceOf(partnerA) + knd.balanceOf(partnerB), totalBefore);
        assertEq(knd.balanceOf(partnerB), 100_000e18 + uint256(toReceiver));
    }

    function testFuzz_lock_expiryWindow(uint64 offset) public {
        offset = uint64(bound(offset, 0, 2 days));
        uint64 expiry = uint64(vm.getBlockTimestamp()) + offset;
        bool valid = offset >= MIN_EXPIRY && offset <= MAX_EXPIRY;
        if (!valid) vm.expectRevert(abi.encodeWithSelector(IPaymentEscrow.BadExpiry.selector, expiry));
        vm.prank(partnerA);
        escrow.lock(ID, partnerB, 1e18, expiry, META);
        assertEq(
            uint8(escrow.intents(ID).status), uint8(valid ? IPaymentEscrow.Status.Locked : IPaymentEscrow.Status.None)
        );
    }

    /// @dev Escrow balance always equals the sum of Locked and Disputed amounts (INV-4, ahead of T1.4).
    function testFuzz_balanceMatchesOpenIntents(uint128[4] memory amounts, uint8 exits) public {
        uint256 open;
        for (uint256 i; i < amounts.length; ++i) {
            uint128 amount = uint128(bound(amounts[i], 1, 10_000e18));
            bytes32 id = keccak256(abi.encode(i));
            vm.prank(partnerA);
            escrow.lock(id, partnerB, amount, _expiry(), META);
            open += amount;

            uint8 exit = (exits >> (i * 2)) & 3;
            if (exit == 1) {
                vm.prank(releaser);
                escrow.release(id);
                open -= amount;
            } else if (exit == 2) {
                vm.prank(partnerB);
                escrow.reject(id);
                open -= amount;
            } else if (exit == 3) {
                vm.prank(partnerA);
                escrow.dispute(id); // still counted: Disputed KND stays in escrow
            }
        }
        assertEq(knd.balanceOf(address(escrow)), open);
    }
}
