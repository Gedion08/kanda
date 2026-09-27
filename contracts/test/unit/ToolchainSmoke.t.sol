// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice Toolchain smoke test for T0.1. Delete when T0.2 adds test/unit/KandaToken.t.sol.
/// @dev Proves the configured EVM target supports transient storage (EIP-1153), which
///      ReentrancyGuardTransient requires (L1 section 1).
contract ToolchainSmokeTest is Test {
    function test_transientStorageAvailable() public {
        uint256 value;
        assembly {
            tstore(0, 42)
            value := tload(0)
        }
        assertEq(value, 42);
    }
}
