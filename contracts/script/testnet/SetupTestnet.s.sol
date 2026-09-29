// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ISafe, ISafeProxyFactory} from "./ISafe.sol";
import {TestnetUSDC, TestnetGold} from "./TestnetTokens.sol";

/// @title SetupTestnet
/// @notice Base Sepolia only. Creates the five Safes of the ADD section 4 role map (Admin, Ops, Compliance, Guardian,
///         Treasury) as 1-of-1 Safes owned by the deployer, and deploys the testnet USDC and gold tokens. Writes the
///         addresses to deployments/base-sepolia-setup.json for config/base-sepolia.json. Add real signers and raise
///         each threshold in the Safe app afterwards; the Safe addresses stay the same.
/// @dev forge script script/testnet/SetupTestnet.s.sol --rpc-url $RPC --private-key $KEY --broadcast
contract SetupTestnet is Script {
    error NotBaseSepolia(uint256 chainId);

    // Safe v1.4.1 canonical deployments, checked on Base Sepolia on 28 Sep 2026.
    address internal constant SAFE_L2_SINGLETON = 0x29fcB43b46531BcA003ddC8FCB67FFE91900C762;
    address internal constant SAFE_PROXY_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address internal constant FALLBACK_HANDLER = 0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99;

    function run() external {
        if (block.chainid != 84_532) revert NotBaseSepolia(block.chainid);

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        address admin = _createSafe(deployer, "admin");
        address ops = _createSafe(deployer, "ops");
        address compliance = _createSafe(deployer, "compliance");
        address guardian = _createSafe(deployer, "guardian");
        address treasury = _createSafe(deployer, "treasury");
        address usdc = address(new TestnetUSDC(deployer));
        address gold = address(new TestnetGold(deployer));
        vm.stopBroadcast();

        string memory k = "setup";
        vm.serializeAddress(k, "adminSafe", admin);
        vm.serializeAddress(k, "opsSafe", ops);
        vm.serializeAddress(k, "complianceSafe", compliance);
        vm.serializeAddress(k, "guardianSafe", guardian);
        vm.serializeAddress(k, "treasurySafe", treasury);
        vm.serializeAddress(k, "usdc", usdc);
        string memory json = vm.serializeAddress(k, "goldToken", gold);
        vm.writeJson(json, string.concat(vm.projectRoot(), "/deployments/base-sepolia-setup.json"));
        console2.log("Setup written to deployments/base-sepolia-setup.json");
    }

    function _createSafe(address owner, string memory name) internal returns (address) {
        address[] memory owners = new address[](1);
        owners[0] = owner;
        bytes memory initializer = abi.encodeCall(
            ISafe.setup, (owners, 1, address(0), "", FALLBACK_HANDLER, address(0), 0, payable(address(0)))
        );
        uint256 salt = uint256(keccak256(abi.encodePacked("kanda.testnet.safe.", name)));
        return ISafeProxyFactory(SAFE_PROXY_FACTORY).createProxyWithNonce(SAFE_L2_SINGLETON, initializer, salt);
    }
}
