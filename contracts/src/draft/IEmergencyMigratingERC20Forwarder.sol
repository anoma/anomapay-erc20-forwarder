// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IEmergencyMigratingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice Migrates ERC20 resources from vulnerable logic references that the forwarder lists.
/// @custom:security-contact security@anoma.foundation
interface IEmergencyMigratingERC20Forwarder {
    /// @notice Emitted when the forwarder replaces its logic reference with a new one.
    /// @param previousLogicRef The logic reference that the forwarder accepted until this call.
    /// @param newLogicRef The logic reference that the forwarder accepts from this call on.
    event LogicRefReplaced(bytes32 indexed previousLogicRef, bytes32 indexed newLogicRef);

    /// @notice Emitted when a resource with a vulnerable logic reference is migrated. No tokens move.
    /// @param token The ERC20 token in the label of the migrated resource.
    /// @param vulnerableLogicRef The logic reference of the migrated resource.
    /// @param nullifier The nullifier of the migrated resource.
    event Migrated(address indexed token, bytes32 indexed vulnerableLogicRef, bytes32 indexed nullifier);

    /// @notice Emitted when the forwarder lists a vulnerable logic reference, whose resources can then migrate.
    /// @param logicRef The vulnerable logic reference.
    event VulnerableLogicRefListed(bytes32 indexed logicRef);

    /// @notice Lists vulnerable logic references and replaces the current logic reference if the new one differs.
    /// @param newLogicRef The logic reference that the forwarder accepts after the call.
    /// @param vulnerableLogicRefs The vulnerable logic references to list. The protocol adapter must deny each one.
    function reinitialize(bytes32 newLogicRef, bytes32[] calldata vulnerableLogicRefs) external;

    /// @notice Returns whether this forwarder lists a logic reference as vulnerable.
    /// @param logicRef The logic reference to check.
    /// @return isVulnerable Whether this forwarder lists the logic reference as vulnerable or not.
    function isLogicRefVulnerable(bytes32 logicRef) external view returns (bool isVulnerable);

    /// @notice Returns the number of vulnerable logic references that this forwarder lists.
    /// @return count The number of vulnerable logic references.
    function vulnerableLogicRefCount() external view returns (uint256 count);

    /// @notice Returns a vulnerable logic reference by index.
    /// @param index The index, in the order in which the forwarder listed the logic references.
    /// @return vulnerableLogicRef The vulnerable logic reference.
    function vulnerableLogicRefAtIndex(uint256 index) external view returns (bytes32 vulnerableLogicRef);

    /// @notice Returns whether the forwarder migrated a resource.
    /// @param nullifier The nullifier of the resource.
    /// @return isMigrated Whether the forwarder migrated the resource or not.
    function isNullifierMigrated(bytes32 nullifier) external view returns (bool isMigrated);

    /// @notice Returns the V1 forwarder of the chain. Resources with its address in their label can migrate too.
    /// @return v1Forwarder The V1 forwarder, or the zero address on a chain without one.
    function getV1Forwarder() external view returns (address v1Forwarder);
}
