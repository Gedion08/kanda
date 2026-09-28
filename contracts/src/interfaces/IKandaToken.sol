// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IKandaToken
/// @notice KND: ERC-20 with permit (EIP-2612), transferWithAuthorization (EIP-3009), blocklist, pause and the
///         mint/burn surface Chainlink CCIP pools expect. Spec: L1 section 3.1.
interface IKandaToken {
    /// @notice Emitted when the Compliance Safe blocks `account` from sending or receiving KND.
    event Blocked(address indexed account);
    /// @notice Emitted when the Compliance Safe unblocks `account`.
    event Unblocked(address indexed account);
    /// @notice Emitted when a token sent to KND by mistake is returned.
    event Rescued(address indexed token, address indexed to, uint256 amount);
    /// @notice Emitted when an EIP-3009 authorization is executed (EIP-3009).
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    /// @notice Emitted when an EIP-3009 authorization is cancelled before use (EIP-3009).
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /// @notice `account` is blocked; it can neither send, receive nor spend KND.
    error AccountBlocked(address account);
    /// @notice rescueERC20 cannot move KND itself.
    error CannotRescueKnd();
    /// @notice A required address argument is zero.
    error ZeroAddress();
    /// @notice The EIP-3009 authorization's validAfter has not passed yet.
    error AuthorizationNotYetValid();
    /// @notice The EIP-3009 authorization's validBefore has passed.
    error AuthorizationExpired();
    /// @notice The EIP-3009 nonce was already used or cancelled.
    error AuthorizationUsedOrCanceled(address authorizer, bytes32 nonce);
    /// @notice The EIP-3009 signature does not recover to the authorizer.
    error InvalidSignature();
    /// @notice receiveWithAuthorization must be called by the payee.
    error CallerMustBePayee(address caller, address payee);

    /// @notice Mint `amount` KND to `to`. MINTER_ROLE only; reverts while paused or if `to` is blocked.
    /// @param to Recipient.
    /// @param amount Amount in base units (18 decimals).
    function mint(address to, uint256 amount) external;

    /// @notice Burn `amount` of the caller's KND. MINTER_ROLE only; reverts while paused.
    /// @param amount Amount in base units.
    function burn(uint256 amount) external;

    /// @notice Burn `amount` of `from`'s KND using the caller's allowance. MINTER_ROLE only; reverts while paused.
    /// @param from Account whose KND is burned.
    /// @param amount Amount in base units.
    function burnFrom(address from, uint256 amount) external;

    /// @notice Block `account` from sending, receiving or spending KND. COMPLIANCE_ROLE only.
    /// @param account Account to block; must not be zero.
    function blockAccount(address account) external;

    /// @notice Unblock `account`. COMPLIANCE_ROLE only.
    /// @param account Account to unblock.
    function unblockAccount(address account) external;

    /// @notice Whether `account` is blocked.
    /// @param account Account to check.
    /// @return True if blocked.
    function isBlocked(address account) external view returns (bool);

    /// @notice Return `amount` of `token` sent to this contract by mistake. DEFAULT_ADMIN_ROLE only.
    /// @param token Token to rescue; must not be KND.
    /// @param to Recipient; must not be zero.
    /// @param amount Amount in the token's base units.
    function rescueERC20(address token, address to, uint256 amount) external;

    /// @notice Stop every KND transfer, mint and burn. PAUSER_ROLE only.
    function pause() external;

    /// @notice Resume KND transfers, mints and burns. UNPAUSER_ROLE only.
    function unpause() external;

    /// @notice Execute a transfer signed by `from` (EIP-3009). Anyone may submit.
    /// @param from Payer and signer.
    /// @param to Payee.
    /// @param value Amount in base units.
    /// @param validAfter Unix time after which the authorization is valid (exclusive).
    /// @param validBefore Unix time before which the authorization is valid (exclusive).
    /// @param nonce Unique 32-byte nonce chosen by the signer.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Execute a transfer signed by `from` (EIP-3009). Only the payee `to` may submit, which stops
    ///         front-running of deposits into contracts.
    /// @param from Payer and signer.
    /// @param to Payee; must be the caller.
    /// @param value Amount in base units.
    /// @param validAfter Unix time after which the authorization is valid (exclusive).
    /// @param validBefore Unix time before which the authorization is valid (exclusive).
    /// @param nonce Unique 32-byte nonce chosen by the signer.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Cancel an unused EIP-3009 authorization.
    /// @param authorizer Signer of the authorization.
    /// @param nonce Nonce to cancel.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external;

    /// @notice Whether `nonce` of `authorizer` has been used or cancelled (EIP-3009).
    /// @param authorizer Signer.
    /// @param nonce Nonce.
    /// @return True if used or cancelled.
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}
