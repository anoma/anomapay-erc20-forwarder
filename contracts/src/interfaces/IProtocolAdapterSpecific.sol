// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IProtocolAdapterSpecific
/// @author Anoma Foundation, 2025
/// @notice The interface of a contract being associated with a specific protocol adapter.
interface IProtocolAdapterSpecific {
    /// @notice Returns the protocol adapter contract address this contract is associated with.
    /// @return protocolAdapter The protocol adapter contract address.
    function getProtocolAdapter() external view returns (address protocolAdapter);
}
