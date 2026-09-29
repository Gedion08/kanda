// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

/// @notice Network parameters from config/<network>.json (L1 section 7, SCP-09). Addresses come only from here.
struct DeployConfig {
    uint256 chainId;
    address usdc;
    address goldToken;
    uint8 goldDecimals;
    address adminSafe;
    address opsSafe;
    address complianceSafe;
    address guardianSafe;
    address treasurySafe;
    address pauseBot;
    address releaser;
    address feeRecipient;
    uint256 timelockDelay;
    uint256 supplyCap;
    uint16 feeBps;
    uint256 usdQtyPerUnit;
    uint256 goldQtyPerUnit;
    TierConfig[] tiers;
}

struct TierConfig {
    uint8 tier;
    uint128 dailyCreate;
    uint128 dailyRedeem;
}

/// @notice Reads config/<network>.json. Big numbers are decimal strings in the file (no floats, AGENTS.md).
library DeployConfigLib {
    using stdJson for string;

    /// @notice No config file exists for this chain.
    error UnsupportedChain(uint256 chainId);

    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Config file name for a chain ID.
    function networkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 84_532) return "base-sepolia";
        if (chainId == 8453) return "base";
        revert UnsupportedChain(chainId);
    }

    /// @notice Load and parse config/<network>.json for `chainId`.
    function load(string memory root, uint256 chainId) internal view returns (DeployConfig memory cfg) {
        string memory json = VM.readFile(string.concat(root, "/config/", networkName(chainId), ".json"));
        cfg = parse(json);
    }

    /// @notice Parse a config JSON document.
    function parse(string memory json) internal view returns (DeployConfig memory cfg) {
        cfg.chainId = json.readUint(".chainId");
        cfg.usdc = json.readAddress(".usdc");
        cfg.goldToken = json.readAddress(".goldToken");
        cfg.goldDecimals = uint8(json.readUint(".goldDecimals"));
        cfg.adminSafe = json.readAddress(".safes.admin");
        cfg.opsSafe = json.readAddress(".safes.ops");
        cfg.complianceSafe = json.readAddress(".safes.compliance");
        cfg.guardianSafe = json.readAddress(".safes.guardian");
        cfg.treasurySafe = json.readAddress(".safes.treasury");
        cfg.pauseBot = json.readAddress(".pauseBot");
        cfg.releaser = json.readAddress(".releaser");
        cfg.feeRecipient = json.readAddress(".feeRecipient");
        cfg.timelockDelay = json.readUint(".timelockDelay");
        cfg.supplyCap = VM.parseUint(json.readString(".supplyCap"));
        cfg.feeBps = uint16(json.readUint(".feeBps"));
        cfg.usdQtyPerUnit = VM.parseUint(json.readString(".usdQtyPerUnit"));
        cfg.goldQtyPerUnit = VM.parseUint(json.readString(".goldQtyPerUnit"));

        uint256 tierCount;
        while (VM.keyExistsJson(json, string.concat(".tiers[", VM.toString(tierCount), "]"))) {
            ++tierCount;
        }
        cfg.tiers = new TierConfig[](tierCount);
        for (uint256 i; i < tierCount; ++i) {
            string memory key = string.concat(".tiers[", VM.toString(i), "]");
            cfg.tiers[i] = TierConfig({
                tier: uint8(json.readUint(string.concat(key, ".tier"))),
                dailyCreate: uint128(VM.parseUint(json.readString(string.concat(key, ".dailyCreate")))),
                dailyRedeem: uint128(VM.parseUint(json.readString(string.concat(key, ".dailyRedeem"))))
            });
        }
    }
}
