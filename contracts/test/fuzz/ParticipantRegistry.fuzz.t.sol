// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IParticipantRegistry} from "../../src/interfaces/IParticipantRegistry.sol";
import {ParticipantRegistryTestBase} from "../unit/ParticipantRegistry.t.sol";

/// @notice Fuzz tests for the daily limits (INV-6: consumed per day at most the tier limit) and the rollover.
contract ParticipantRegistryFuzzTest is ParticipantRegistryTestBase {
    /// @dev Replays a random sequence of creates across days against a model of the limit, per UTC day.
    function testFuzz_consumeCreate_neverExceedsDailyLimit(uint256[12] memory amounts, uint8[12] memory hoursForward)
        public
    {
        uint256 day = vm.getBlockTimestamp() / 1 days;
        uint256 used;

        for (uint256 i; i < amounts.length; ++i) {
            vm.warp(vm.getBlockTimestamp() + uint256(hoursForward[i] % 30) * 1 hours);
            if (vm.getBlockTimestamp() / 1 days != day) {
                day = vm.getBlockTimestamp() / 1 days;
                used = 0;
            }

            uint256 amount = bound(amounts[i], 0, TIER1_LIMIT);
            uint256 left = TIER1_LIMIT - used;
            if (amount > left) {
                vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, amount, left));
                _consumeCreate(ap, amount);
            } else {
                _consumeCreate(ap, amount);
                used += amount;
            }

            (uint256 create,) = registry.remaining(ap);
            assertEq(create, TIER1_LIMIT - used);
            assertLe(used, TIER1_LIMIT);
        }
    }

    function testFuzz_remaining_saturatesWhenLimitLowered(uint128 consumed, uint128 newLimit) public {
        consumed = uint128(bound(consumed, 0, TIER1_LIMIT));
        _consumeRedeem(ap, consumed);
        _setTier(1, TIER1_LIMIT, newLimit);

        (, uint256 redeem) = registry.remaining(ap);
        assertEq(redeem, newLimit > consumed ? newLimit - consumed : 0);
    }
}
