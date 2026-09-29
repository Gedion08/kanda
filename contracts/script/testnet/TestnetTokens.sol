// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TestnetUSDC
/// @notice Base Sepolia stand-in for USDC (P0 build order step 4): 6 decimals, owner-only mint. Never deploy on mainnet.
contract TestnetUSDC is ERC20, Ownable {
    constructor(address owner_) ERC20("Kanda Testnet USD Coin", "tUSDC") Ownable(owner_) {}

    /// @notice Mint test USDC. Owner only.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @title TestnetGold
/// @notice Base Sepolia stand-in for DGLD (ADR-010; P0 build order step 4): 18 decimals, and the issuer powers the
///         vault must survive as owner-only toggles: a transfer fee, a pause of all transfers, and a blacklist.
///         Never deploy on mainnet.
contract TestnetGold is ERC20, Ownable {
    error TokenPaused();
    error AddressBlacklisted(address account);
    error FeeTooHigh(uint16 feeBps);

    event TransferFeeSet(uint16 feeBps);
    event PausedSet(bool paused);
    event BlacklistedSet(address indexed account, bool blacklisted);

    uint16 public transferFeeBps;
    bool public paused;
    mapping(address account => bool) public blacklisted;

    constructor(address owner_) ERC20("Kanda Testnet Gold", "tDGLD") Ownable(owner_) {}

    /// @notice Mint test gold. Owner only.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Charge `feeBps` on every transfer, burned. Owner only; at most 10%.
    function setTransferFeeBps(uint16 feeBps) external onlyOwner {
        if (feeBps > 1000) revert FeeTooHigh(feeBps);
        transferFeeBps = feeBps;
        emit TransferFeeSet(feeBps);
    }

    /// @notice Pause or resume all transfers. Owner only.
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedSet(paused_);
    }

    /// @notice Blacklist or clear `account`. Owner only.
    function setBlacklisted(address account, bool value) external onlyOwner {
        blacklisted[account] = value;
        emit BlacklistedSet(account, value);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (paused) revert TokenPaused();
        if (blacklisted[from]) revert AddressBlacklisted(from);
        if (blacklisted[to]) revert AddressBlacklisted(to);

        uint256 fee = (from != address(0) && to != address(0)) ? value * transferFeeBps / 10_000 : 0;
        if (fee > 0) super._update(from, address(0), fee);
        super._update(from, to, value - fee);
    }
}
