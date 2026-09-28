// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IMigratingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice Re-issues ERC20 resources whose logic reference the forwarder retired after a proof system version turned
/// out to be forgeable.
/// @custom:security-contact security@anoma.foundation
interface IMigratingERC20Forwarder {
    /// @notice Emitted when the forwarder rotates its logic reference and opens the outgoing one for migrations.
    /// @param retiredLogicRef The logic reference the forwarder accepted until this call.
    /// @param migrationRoot The commitment tree root the retired resources are migrated against.
    /// @param newLogicRef The logic reference the forwarder accepts from this call on.
    event LogicRefRetired(bytes32 indexed retiredLogicRef, bytes32 indexed migrationRoot, bytes32 indexed newLogicRef);

    /// @notice Emitted when a retired resource is migrated. No tokens move, so the amount states what the re-issued
    /// resource carries, not what the forwarder received.
    /// @param token The ERC20 token the migrated resource is labelled with.
    /// @param retiredLogicRef The logic reference the migrated resource carries.
    /// @param nullifier The nullifier of the migrated resource.
    /// @param amount The quantity the migrated resource carries.
    event Migrated(address indexed token, bytes32 indexed retiredLogicRef, bytes32 indexed nullifier, uint128 amount);

    /// @notice Retires the current logic reference against a commitment tree root and rotates to a new one. The
    /// protocol adapter must be paused, and it must hold the root.
    /// @param newLogicRef The logic reference the forwarder accepts after the call.
    /// @param migrationRoot The commitment tree root the retired resources are migrated against. It is the last root
    /// the incident leaves trustworthy.
    function reinitialize(bytes32 newLogicRef, bytes32 migrationRoot) external;

    /// @notice Returns the commitment tree root a retired logic reference is migrated against.
    /// @param retiredLogicRef The retired logic reference.
    /// @return migrationRoot The root, or zero if the forwarder never retired this logic reference.
    function getMigrationRoot(bytes32 retiredLogicRef) external view returns (bytes32 migrationRoot);

    /// @notice Returns how many logic references the forwarder has retired.
    /// @return count The number of retired logic references.
    function retiredLogicRefCount() external view returns (uint256 count);

    /// @notice Returns a retired logic reference and its migration root by index.
    /// @param index The index to read, in retirement order.
    /// @return retiredLogicRef The retired logic reference.
    /// @return migrationRoot The root the retired resources are migrated against.
    function retiredLogicRefAtIndex(uint256 index)
        external
        view
        returns (bytes32 retiredLogicRef, bytes32 migrationRoot);

    /// @notice Checks whether a resource has been migrated.
    /// @param nullifier The nullifier of the resource.
    /// @return isMigrated Whether the forwarder recorded a migration for this nullifier or not.
    function isNullifierMigrated(bytes32 nullifier) external view returns (bool isMigrated);
}
