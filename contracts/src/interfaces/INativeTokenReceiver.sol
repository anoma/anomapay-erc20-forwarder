// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title INativeTokenReceiver
/// @author Anoma Foundation, 2026
/// @notice The interface of a contract receiving native tokens.
interface INativeTokenReceiver {
    /// @notice Emitted when a native tokens have been received
    /// @dev This event is intended to be emitted in the `receive` function and is therefore bound by the gas
    /// limitations for `send`/`transfer` calls introduced by ERC-2929 (https://eips.ethereum.org/EIPS/eip-2929).
    /// @param sender The address of the sender.
    /// @param amount The amount of native tokens deposited.
    event NativeTokenReceived(address sender, uint256 amount);

    /// @notice Receives native tokens.
    receive() external payable;
}
