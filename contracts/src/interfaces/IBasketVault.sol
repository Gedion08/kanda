// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IBasketVault
/// @notice Holds the basket reserves and runs in-kind create and redeem of KND. Sole MINTER_ROLE holder in P1.
///         Never reads a price oracle. Spec: L1 section 3.3.
interface IBasketVault {
    /// @notice One basket leg: `qtyPerUnit` base units of `asset` per 1e18 KND.
    struct Leg {
        address asset;
        uint256 qtyPerUnit;
    }

    /// @notice Emitted on create. `amountsIn` are the amounts the vault actually received, per leg.
    event Created(address indexed participant, address indexed to, uint256 kndGross, uint256 fee, uint256[] amountsIn);
    /// @notice Emitted on redeem. `amountsOut` are the amounts the vault sent, per leg.
    event Redeemed(
        address indexed participant, address indexed to, uint256 kndGross, uint256 fee, uint256[] amountsOut
    );
    /// @notice Emitted when a basket version is set (version 1 at genesis).
    event BasketVersionSet(uint32 indexed version, Leg[] legs);
    /// @notice Emitted when the supply cap is set.
    event SupplyCapSet(uint256 cap);
    /// @notice Emitted when the fee or its recipient is set.
    event FeeSet(uint16 feeBps, address recipient);
    /// @notice Emitted when creation is paused; redeem continues.
    event CreatePaused(address account);
    /// @notice Emitted when creation is unpaused.
    event CreateUnpaused(address account);

    /// @notice Minting would take total supply above the cap.
    error SupplyCapExceeded(uint256 newSupply, uint256 cap);
    /// @notice A redeem leg pays less than the caller's minimum.
    error SlippageOut(uint256 leg, uint256 amount, uint256 min);
    /// @notice A create mints less net KND than the caller's minimum.
    error MintBelowMin(uint256 minted, uint256 minOut);
    /// @notice A leg would not be fully backed (reserved for basket changes, P3).
    error BasketNotBacked(uint256 leg);
    /// @notice Creation is paused.
    error CreationPaused();
    /// @notice The fee is above 100 bps.
    error FeeTooHigh(uint16 feeBps);
    /// @notice An amount argument is zero.
    error ZeroAmount();
    /// @notice A required address argument is zero.
    error ZeroAddress();
    /// @notice An array has the wrong length.
    error LengthMismatch(uint256 expected, uint256 actual);
    /// @notice The basket is empty, or has a zero or repeated asset, or a zero quantity.
    error InvalidBasket();

    /// @notice Deliver the basket for `kndAmount` KND and mint KND to `to`. Active participants only.
    /// @dev Pulls ceil(kndAmount * qtyPerUnit / 1e18) of each leg. With a fee-on-transfer leg, the scarcest leg
    ///      decides the gross mint and any excess stays as surplus backing.
    /// @param kndAmount KND to create, gross, in base units.
    /// @param minKndOut Minimum net KND to receive after the fee.
    /// @param to Recipient of the net KND; must be non-zero and not blocked.
    /// @return kndOut Net KND minted to `to`.
    function createInKind(uint256 kndAmount, uint256 minKndOut, address to) external returns (uint256 kndOut);

    /// @notice Return `kndAmount` KND and receive the basket for the net amount. Active participants only.
    /// @dev The fee stays in circulation (sent to the fee recipient); the net is burned and paid out
    ///      floor(net * qtyPerUnit / 1e18) per leg. Works while creation is paused.
    /// @param kndAmount KND to redeem, gross, in base units. The caller must have approved the vault.
    /// @param minAmountsOut Minimum amount per leg, one entry per leg.
    /// @param to Recipient of the basket assets; must be non-zero.
    /// @return amountsOut Amount sent per leg.
    function redeemInKind(uint256 kndAmount, uint256[] calldata minAmountsOut, address to)
        external
        returns (uint256[] memory amountsOut);

    /// @notice What createInKind would pull and mint, assuming no transfer fee on any leg.
    /// @param kndAmount KND to create, gross.
    /// @return amountsIn Amount pulled per leg.
    /// @return kndOutNet Net KND after the fee.
    function previewCreate(uint256 kndAmount) external view returns (uint256[] memory amountsIn, uint256 kndOutNet);

    /// @notice What redeemInKind would pay per leg.
    /// @param kndAmount KND to redeem, gross.
    /// @return amountsOut Amount paid per leg.
    function previewRedeem(uint256 kndAmount) external view returns (uint256[] memory amountsOut);

    /// @notice The current basket.
    /// @return version Basket version.
    /// @return Legs, in order.
    function legs() external view returns (uint32 version, Leg[] memory);

    /// @notice Vault balance over required backing, per leg, in bps (10000 = 100%).
    /// @dev Required backing is ceil(totalSupply * qtyPerUnit / 1e18). Returns type(uint256).max per leg while
    ///      supply is zero.
    /// @return ratiosBps One ratio per leg.
    function coverage() external view returns (uint256[] memory ratiosBps);

    /// @notice Whether creation is paused.
    /// @return True if createInKind is stopped.
    function createPaused() external view returns (bool);

    /// @notice Set the supply cap. LIMITS_ADMIN_ROLE (timelock) only. A cap below supply stops creation.
    /// @param cap New cap in KND base units.
    function setSupplyCap(uint256 cap) external;

    /// @notice Set the fee and its recipient. LIMITS_ADMIN_ROLE (timelock) only.
    /// @param feeBps Fee in bps, at most 100.
    /// @param recipient Fee recipient; must be non-zero.
    function setFee(uint16 feeBps, address recipient) external;

    /// @notice Stop create and redeem. PAUSER_ROLE only.
    function pause() external;

    /// @notice Resume create and redeem. UNPAUSER_ROLE only.
    function unpause() external;

    /// @notice Stop create only; redeem continues. PAUSER_ROLE only.
    function pauseCreate() external;

    /// @notice Resume create. UNPAUSER_ROLE only.
    function unpauseCreate() external;
}
