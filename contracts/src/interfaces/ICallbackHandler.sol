// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ICallbackHandler
/// @author Anoma Foundation, 2026
/// @notice The interface of a contract being associated with a specific resource logic function reference.
interface ICallbackHandler {
    /// @notice Emitted when `_handleCallback` is called.
    /// @param sender Who called the callback.
    /// @param sig The function signature.
    /// @param data The calldata.
    event CallbackReceived(address sender, bytes4 indexed sig, bytes data);

    /// @notice Registers a magic number for a callback function selector.
    /// @param callbackSelector The selector of the callback function.
    /// @param magicNumber The magic number to be registered for the callback function selector.
    function registerCallback(bytes4 callbackSelector, bytes4 magicNumber) external;
}
