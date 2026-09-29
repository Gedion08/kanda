// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ParticipantRegistry} from "../../src/registry/ParticipantRegistry.sol";
import {BasketVault} from "../../src/vault/BasketVault.sol";
import {IParticipantRegistry} from "../../src/interfaces/IParticipantRegistry.sol";
import {DeployConfig, DeployConfigLib} from "../lib/DeployConfig.sol";
import {ISafe, SafeExec} from "./ISafe.sol";
import {TestnetUSDC, TestnetGold} from "./TestnetTokens.sol";

/// @title SeedTestnet
/// @notice Base Sepolia only. Through the Ops Safe, registers the deployer as a tier-1 authorized participant, then
///         mints testnet basket assets to it and creates `SEED_KND` KND, so the transparency page (T0.7) has live
///         supply, balances and coverage to read. Every step goes through the real roles: Ops Safe, vault, registry.
/// @dev SEED_KND=1000 forge script script/testnet/SeedTestnet.s.sol --rpc-url $RPC --private-key $KEY --broadcast
contract SeedTestnet is Script {
    using stdJson for string;

    error NotBaseSepolia(uint256 chainId);

    function run() external {
        if (block.chainid != 84_532) revert NotBaseSepolia(block.chainid);
        DeployConfig memory cfg = DeployConfigLib.load(vm.projectRoot(), block.chainid);
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/deployments/base-sepolia.json"));
        address registry = json.readAddress(".participantRegistry");
        address vault = json.readAddress(".basketVault");
        uint256 kndAmount = vm.envOr("SEED_KND", uint256(1000)) * 1e18;

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        SafeExec.exec(
            ISafe(cfg.opsSafe),
            deployer,
            registry,
            abi.encodeCall(
                ParticipantRegistry.setAccount, (deployer, IParticipantRegistry.Kind.Participant, uint8(1), true)
            )
        );

        (uint256[] memory amountsIn,) = BasketVault(vault).previewCreate(kndAmount);
        TestnetUSDC(cfg.usdc).mint(deployer, amountsIn[0]);
        TestnetGold(cfg.goldToken).mint(deployer, amountsIn[1]);
        IERC20(cfg.usdc).approve(vault, amountsIn[0]);
        IERC20(cfg.goldToken).approve(vault, amountsIn[1]);
        uint256 out = BasketVault(vault).createInKind(kndAmount, 0, deployer);
        vm.stopBroadcast();

        console2.log("Seeded: net KND minted to deployer", out);
    }
}
