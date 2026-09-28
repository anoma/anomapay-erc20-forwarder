// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ILogicRefDenylist
/// @author Anoma Foundation, 2026
/// @notice The part of the protocol adapter's logic reference denylist that this draft reads. The draft declares it
/// until a pa-evm release carries `ILogicRefDenylist`.
/// @custom:security-contact security@anoma.foundation
interface ILogicRefDenylist {
    /// @notice Returns whether the denylist contains a given logic reference or not.
    /// @param logicRef The logic reference to check.
    /// @return isDenied Whether the logic reference is denied or not.
    function isLogicRefDenied(bytes32 logicRef) external view returns (bool isDenied);
}
