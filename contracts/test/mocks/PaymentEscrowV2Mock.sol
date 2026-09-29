// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PaymentEscrow} from "../../src/payments/PaymentEscrow.sol";

/// @notice Upgrade target for UUPS tests. Adds one view so tests can tell the implementations apart.
contract PaymentEscrowV2Mock is PaymentEscrow {
    function version() external pure returns (uint256) {
        return 2;
    }
}
