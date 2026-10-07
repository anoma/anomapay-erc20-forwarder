// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IEmergencyMigratingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice Migrates ERC20 resources from vulnerable logic references that the forwarder replaced.
/// @custom:security-contact security@anoma.foundation
interface IEmergencyMigratingERC20Forwarder {
    /// @notice Emitted when the forwarder replaces its vulnerable logic reference with a new one.
    /// @param vulnerableLogicRef The logic reference that the forwarder accepted until this call.
    /// @param newLogicRef The logic reference that the forwarder accepts from this call on.
    event LogicRefReplaced(bytes32 indexed vulnerableLogicRef, bytes32 indexed newLogicRef);

    /// @notice Emitted when a resource with a vulnerable logic reference is migrated. No tokens move.
    /// @param token The ERC20 token in the label of the migrated resource.
    /// @param vulnerableLogicRef The logic reference of the migrated resource.
    /// @param nullifier The nullifier of the migrated resource.
    event Migrated(address indexed token, bytes32 indexed vulnerableLogicRef, bytes32 indexed nullifier);

    /// @notice Replaces the current logic reference, which is vulnerable, with a new one.
    /// @param newLogicRef The logic reference that the forwarder accepts after the call.
    function reinitialize(bytes32 newLogicRef) external;

    /// @notice Returns whether this forwarder replaced a logic reference as vulnerable.
    /// @param logicRef The logic reference to check.
    /// @return isVulnerable Whether this forwarder replaced the logic reference as vulnerable or not.
    function isLogicRefVulnerable(bytes32 logicRef) external view returns (bool isVulnerable);

    /// @notice Returns the number of vulnerable logic references that this forwarder replaced.
    /// @return count The number of vulnerable logic references.
    function vulnerableLogicRefCount() external view returns (uint256 count);

    /// @notice Returns a vulnerable logic reference by index.
    /// @param index The index, in the order in which the forwarder replaced the logic references.
    /// @return vulnerableLogicRef The vulnerable logic reference.
    function vulnerableLogicRefAtIndex(uint256 index) external view returns (bytes32 vulnerableLogicRef);

    /// @notice Returns whether the forwarder migrated a resource.
    /// @param nullifier The nullifier of the resource.
    /// @return isMigrated Whether the forwarder migrated the resource or not.
    function isNullifierMigrated(bytes32 nullifier) external view returns (bool isMigrated);
}
