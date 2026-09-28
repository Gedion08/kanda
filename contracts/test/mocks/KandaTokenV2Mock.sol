// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {KandaToken} from "../../src/token/KandaToken.sol";

/// @notice Upgrade target for UUPS tests. Adds one view so tests can tell the implementations apart.
contract KandaTokenV2Mock is KandaToken {
    function version() external pure returns (uint256) {
        return 2;
    }
}
