// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IFallbackHandler
/// @author Anoma Foundation, 2026
/// @notice The interface of a contract handling fallbacks.
interface IFallbackHandler {
    /// @notice Emitted when a fallback was handled by the fallback handler.
    /// @param sender The sender of the fallback function call.
    /// @param selector The selector of the calling function.
    /// @param data The calldata.
    event FallbackHandled(address indexed sender, bytes4 indexed selector, bytes data);

    /// @notice Registers a magic number for a callback function selector.
    /// @param selector The selector of the callback function.
    /// @param magicNumber The magic number to be registered for the callback function selector.
    function registerSelector(bytes4 selector, bytes4 magicNumber) external;
}
