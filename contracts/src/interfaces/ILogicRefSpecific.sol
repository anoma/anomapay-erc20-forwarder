// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ILogicRefSpecific
/// @author Anoma Foundation, 2025
/// @notice The interface of a contract being associated with a specific logic reference.
interface ILogicRefSpecific {
    /// @notice Returns the logic reference this contract is associated with.
    /// @return logicRef The logic reference.
    function getLogicRef() external view returns (bytes32 logicRef);
}
