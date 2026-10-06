// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ILogicRefDenylist
/// @author Anoma Foundation, 2026
/// @notice The function of the protocol adapter's logic reference denylists that this draft reads.
/// @dev Replace it with the pa-evm interface when a pa-evm release contains it.
/// @custom:security-contact security@anoma.foundation
interface ILogicRefDenylist {
    /// @notice Returns whether a denylist contains a given logic reference or not.
    /// @param logicRef The logic reference to check.
    /// @param consumed `true` for the denylist for consumed resources, `false` for the one for created resources.
    /// @return isDenied Whether the denylist contains the logic reference or not.
    function isLogicRefDenied(bytes32 logicRef, bool consumed) external view returns (bool isDenied);
}
