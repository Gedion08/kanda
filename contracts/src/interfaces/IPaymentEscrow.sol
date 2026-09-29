// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IPaymentEscrow
/// @notice Locks KND per payment intent between two registered partners until it is released to the receiver,
///         refunded to the sender, or split by the arbiter after a dispute. Spec: L1 section 3.4.
/// @dev batchRelease (P2) is not in the P1 interface (review C-13, SCP-13); the escrow is UUPS, so P2 adds it.
interface IPaymentEscrow {
    enum Status {
        None,
        Locked,
        Released,
        Refunded,
        Disputed,
        Resolved
    }

    struct Intent {
        address sender;
        address receiver;
        uint128 amount;
        uint64 expiry;
        Status status;
        bytes32 metadataHash;
    }

    /// @notice Emitted when the sender locks `amount` KND for `receiver` until `expiry`.
    event Locked(
        bytes32 indexed intentId,
        address indexed sender,
        address indexed receiver,
        uint128 amount,
        uint64 expiry,
        bytes32 metadataHash
    );
    /// @notice Emitted when the KND goes to the receiver.
    event Released(bytes32 indexed intentId, address indexed by);
    /// @notice Emitted when the KND goes back to the sender: rejected by the receiver, or refunded after expiry.
    event Refunded(bytes32 indexed intentId, address indexed by);
    /// @notice Emitted when the sender or receiver disputes a locked intent before expiry.
    event Disputed(bytes32 indexed intentId, address indexed by);
    /// @notice Emitted when the arbiter splits a disputed intent.
    event Resolved(bytes32 indexed intentId, uint128 toReceiver, uint128 toSender);
    /// @notice Emitted when the allowed expiry window changes.
    event ExpiryBoundsSet(uint64 minExpiry, uint64 maxExpiry);

    /// @notice `intentId` has been used before; ids are never reused.
    error IntentExists(bytes32 intentId);
    /// @notice The intent is not in a status that allows this call.
    error BadStatus(bytes32 intentId, Status status);
    /// @notice refund was called before the intent's expiry.
    error NotExpired(bytes32 intentId);
    /// @notice The caller may not act on this intent.
    error Unauthorized(address caller);
    /// @notice `expiry` is outside now + minExpiry to now + maxExpiry, or dispute was called at or after expiry.
    error BadExpiry(uint64 expiry);
    /// @notice The bounds are invalid: need 0 < minExpiry <= maxExpiry.
    error InvalidExpiryBounds(uint64 minExpiry, uint64 maxExpiry);
    /// @notice The arbiter's share for the receiver exceeds the locked amount.
    error InvalidSplit(uint128 toReceiver, uint128 amount);
    /// @notice The sender and receiver are the same account.
    error SameParty(address account);
    /// @notice The amount is zero.
    error ZeroAmount();
    /// @notice A required address argument is zero (initializer).
    error ZeroAddress();

    /// @notice Lock `amount` KND from the caller for `receiver`. Both must be active partners, distinct and unblocked.
    /// @param intentId keccak256 of the off-chain intent id and chain id (SCP-04); never reused.
    /// @param receiver The receiving partner.
    /// @param amount KND in base units; the caller must have approved the escrow.
    /// @param expiry Unix time; must be within now + minExpiry and now + maxExpiry.
    /// @param metadataHash Hash of the Travel Rule and invoice payload kept off-chain.
    function lock(bytes32 intentId, address receiver, uint128 amount, uint64 expiry, bytes32 metadataHash) external;

    /// @notice Pay a locked intent to its receiver. The sender or RELEASER_ROLE only.
    /// @param intentId The intent.
    function release(bytes32 intentId) external;

    /// @notice Decline a locked intent and return the KND to the sender now. The receiver only.
    /// @param intentId The intent.
    function reject(bytes32 intentId) external;

    /// @notice Return a locked intent to its sender once it has expired. Anyone may call.
    /// @param intentId The intent.
    function refund(bytes32 intentId) external;

    /// @notice Freeze a locked intent for the arbiter. The sender or receiver only, before expiry.
    /// @param intentId The intent.
    function dispute(bytes32 intentId) external;

    /// @notice Split a disputed intent: `toReceiver` to the receiver, the rest to the sender. ARBITER_ROLE only.
    /// @param intentId The intent.
    /// @param toReceiver KND for the receiver; at most the locked amount.
    function resolve(bytes32 intentId, uint128 toReceiver) external;

    /// @notice Set the allowed expiry window. LIMITS_ADMIN_ROLE (timelock) only.
    /// @param minExpiry Shortest allowed lock, in seconds; above zero.
    /// @param maxExpiry Longest allowed lock, in seconds; at least minExpiry.
    function setExpiryBounds(uint64 minExpiry, uint64 maxExpiry) external;

    /// @notice Stop every intent operation. PAUSER_ROLE only.
    function pause() external;

    /// @notice Resume intent operations. UNPAUSER_ROLE only.
    function unpause() external;

    /// @notice An intent by id; status None if it has never been used.
    /// @param intentId The intent.
    /// @return The intent.
    function intents(bytes32 intentId) external view returns (Intent memory);
}
