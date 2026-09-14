// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IERC20ForwarderV1
/// @author Anoma Foundation, 2026
/// @notice The deployed V1 emergency migration and configuration API.
interface IERC20ForwarderV1 {
    /// @notice Forwards a call after the PA stops, restricted to the permanent emergency caller.
    /// @param input The ABI-encoded V1 forwarder input.
    /// @return output Empty bytes on success.
    function forwardEmergencyCall(bytes calldata input) external returns (bytes memory output);

    /// @notice Assigns the emergency caller once, restricted to the committee after the PA stops.
    /// @param newEmergencyCaller The permanent caller.
    function setEmergencyCaller(address newEmergencyCaller) external;

    /// @notice Returns the assigned emergency caller.
    /// @return caller The caller, or zero before assignment.
    function getEmergencyCaller() external view returns (address caller);

    /// @notice Returns the associated protocol adapter.
    /// @return protocolAdapter The V1 protocol adapter.
    function getProtocolAdapter() external view returns (address protocolAdapter);

    /// @notice Returns the resource logic reference.
    /// @return logicRef The V1 ERC20 resource logic reference.
    function getLogicRef() external view returns (bytes32 logicRef);
}
