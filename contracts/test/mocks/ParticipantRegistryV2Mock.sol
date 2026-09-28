// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ParticipantRegistry} from "../../src/registry/ParticipantRegistry.sol";

/// @notice Upgrade target for UUPS tests. Adds one view so tests can tell the implementations apart.
contract ParticipantRegistryV2Mock is ParticipantRegistry {
    function version() external pure returns (uint256) {
        return 2;
    }
}
