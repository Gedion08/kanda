// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {KandaDeployer} from "./lib/KandaDeployer.sol";
import {DeployConfig, DeployConfigLib} from "./lib/DeployConfig.sol";
import {Deployment} from "./lib/RoleMap.sol";

/// @title Deploy
/// @notice Reads config/<network>.json, deploys the P0 contracts in L1 section 7 order, sets tiers, wires the ADD
///         section 4 role map, renounces every deployer role, verifies the map, and writes deployments/<network>.json.
/// @dev forge script script/Deploy.s.sol --rpc-url $RPC --private-key $KEY --broadcast
contract Deploy is Script, KandaDeployer {
    function run() external returns (Deployment memory d) {
        DeployConfig memory cfg = DeployConfigLib.load(vm.projectRoot(), block.chainid);
        uint256 startBlock = block.number;

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        d = _deployAll(cfg, deployer);
        vm.stopBroadcast();

        _write(d, deployer, startBlock);
    }

    function _write(Deployment memory d, address deployer, uint256 startBlock) internal {
        string memory k = "deployment";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeUint(k, "startBlock", startBlock);
        vm.serializeAddress(k, "deployer", deployer);
        vm.serializeAddress(k, "timelock", d.timelock);
        vm.serializeAddress(k, "kandaToken", d.kandaToken);
        vm.serializeAddress(k, "kandaTokenImplementation", d.kandaTokenImpl);
        vm.serializeAddress(k, "participantRegistry", d.registry);
        vm.serializeAddress(k, "participantRegistryImplementation", d.registryImpl);
        vm.serializeAddress(k, "basketVault", d.vault);
        string memory json = vm.serializeAddress(k, "basketVaultImplementation", d.vaultImpl);
        vm.writeJson(
            json, string.concat(vm.projectRoot(), "/deployments/", DeployConfigLib.networkName(block.chainid), ".json")
        );
    }
}
