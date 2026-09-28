// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice The parts of Safe v1.4.1 the testnet scripts use.
interface ISafe {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures
    ) external payable returns (bool);

    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}

/// @notice Safe v1.4.1 proxy factory.
interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes calldata initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

/// @notice Executes a transaction through a Safe whose sole owner is the broadcaster. The signature is Safe's
///         "approved by msg.sender" form (v = 1, r = owner), valid only when the owner itself submits.
library SafeExec {
    function exec(ISafe safe, address owner, address to, bytes memory data) internal {
        bytes memory signature = abi.encodePacked(bytes32(uint256(uint160(owner))), bytes32(0), uint8(1));
        safe.execTransaction(to, 0, data, 0, 0, 0, 0, address(0), payable(address(0)), signature);
    }
}
