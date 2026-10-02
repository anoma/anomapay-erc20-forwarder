// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IMigratingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice Migrates ERC20 resources from logic references that the forwarder retired.
/// @custom:security-contact security@anoma.foundation
interface IMigratingERC20Forwarder {
    /// @notice Emitted when the forwarder retires its logic reference and accepts a new one.
    /// @param retiredLogicRef The logic reference that the forwarder accepted until this call.
    /// @param newLogicRef The logic reference that the forwarder accepts from this call on.
    event LogicRefRetired(bytes32 indexed retiredLogicRef, bytes32 indexed newLogicRef);

    /// @notice Emitted when a resource with a retired logic reference is migrated. No tokens move.
    /// @param token The ERC20 token in the label of the migrated resource.
    /// @param retiredLogicRef The logic reference of the migrated resource.
    /// @param nullifier The nullifier of the migrated resource.
    event Migrated(address indexed token, bytes32 indexed retiredLogicRef, bytes32 indexed nullifier);

    /// @notice Retires the current logic reference and accepts a new one.
    /// @param newLogicRef The logic reference that the forwarder accepts after the call.
    function reinitialize(bytes32 newLogicRef) external;

    /// @notice Returns whether the forwarder retired a logic reference.
    /// @param logicRef The logic reference to check.
    /// @return isRetired Whether the forwarder retired the logic reference or not.
    function isLogicRefRetired(bytes32 logicRef) external view returns (bool isRetired);

    /// @notice Returns the number of logic references that the forwarder retired.
    /// @return count The number of retired logic references.
    function retiredLogicRefCount() external view returns (uint256 count);

    /// @notice Returns a retired logic reference by index.
    /// @param index The index, in the order of retirement.
    /// @return retiredLogicRef The retired logic reference.
    function retiredLogicRefAtIndex(uint256 index) external view returns (bytes32 retiredLogicRef);

    /// @notice Returns whether the forwarder migrated a resource.
    /// @param nullifier The nullifier of the resource.
    /// @return isMigrated Whether the forwarder migrated the resource or not.
    function isNullifierMigrated(bytes32 nullifier) external view returns (bool isMigrated);
}
