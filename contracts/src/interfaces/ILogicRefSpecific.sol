// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ILogicRefSpecific
/// @author Anoma Foundation, 2025
/// @notice The interface of a contract being associated with a specific resource logic function reference.
interface ILogicRefSpecific {
    /// @notice Returns the resource logic function reference this contract is associated with.
    /// @return logicRef The resource logic function reference.
    function getLogicRef() external view returns (bytes32 logicRef);
}
