// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BasketVault} from "../../src/vault/BasketVault.sol";

/// @notice Upgrade target for UUPS tests. Adds one view so tests can tell the implementations apart.
contract BasketVaultV2Mock is BasketVault {
    function version() external pure returns (uint256) {
        return 2;
    }
}
