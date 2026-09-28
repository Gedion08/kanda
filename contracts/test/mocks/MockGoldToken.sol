// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Gold token modelled on DGLD (ADR-010): 18 decimals, and the issuer powers the vault must survive,
///         as test toggles: a transfer fee (an upgrade could add one), a pause of all transfers, and a blacklist.
contract MockGoldToken is ERC20 {
    error TokenPaused();
    error AddressBlacklisted(address account);

    uint16 public transferFeeBps;
    bool public paused;
    mapping(address account => bool) public blacklisted;

    constructor() ERC20("Mock DGLD", "DGLD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTransferFeeBps(uint16 feeBps) external {
        transferFeeBps = feeBps;
    }

    function setPaused(bool paused_) external {
        paused = paused_;
    }

    function setBlacklisted(address account, bool value) external {
        blacklisted[account] = value;
    }

    /// @dev On transfers (not mint or burn), the fee is burned, so the recipient receives value minus the fee.
    function _update(address from, address to, uint256 value) internal override {
        if (paused) revert TokenPaused();
        if (blacklisted[from]) revert AddressBlacklisted(from);
        if (blacklisted[to]) revert AddressBlacklisted(to);

        uint256 fee = (from != address(0) && to != address(0)) ? value * transferFeeBps / 10_000 : 0;
        if (fee > 0) super._update(from, address(0), fee);
        super._update(from, to, value - fee);
    }
}
