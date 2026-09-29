// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {KandaDeployer} from "./lib/KandaDeployer.sol";
import {DeployConfig, DeployConfigLib} from "./lib/DeployConfig.sol";
import {Deployment} from "./lib/RoleMap.sol";

/// @title VerifyRoles
/// @notice Read-only (L1 section 7 step 9): reads deployments/<network>.json and config/<network>.json and reverts
///         RoleMismatch if any known address holds a role the ADD section 4 map does not give it, or lacks one it does.
/// @dev forge script script/VerifyRoles.s.sol --rpc-url $RPC
contract VerifyRoles is Script, KandaDeployer {
    using stdJson for string;

    function run() external view {
        DeployConfig memory cfg = DeployConfigLib.load(vm.projectRoot(), block.chainid);
        string memory json = vm.readFile(
            string.concat(vm.projectRoot(), "/deployments/", DeployConfigLib.networkName(block.chainid), ".json")
        );
        Deployment memory d = Deployment({
            timelock: json.readAddress(".timelock"),
            kandaToken: json.readAddress(".kandaToken"),
            kandaTokenImpl: json.readAddress(".kandaTokenImplementation"),
            registry: json.readAddress(".participantRegistry"),
            registryImpl: json.readAddress(".participantRegistryImplementation"),
            vault: json.readAddress(".basketVault"),
            vaultImpl: json.readAddress(".basketVaultImplementation")
        });
        _verifyRoles(cfg, d, json.readAddress(".deployer"));
        console2.log("VerifyRoles: role map matches ADD section 4 on chain", block.chainid);
    }
}
