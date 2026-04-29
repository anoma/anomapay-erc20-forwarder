// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {INativeTokenReceiver} from "../interfaces/INativeTokenReceiver.sol";

/// @title NativeTokenReceiver
/// @author Anoma Foundation, 2026
/// @notice A contract receiving native tokens.
/// @custom:security-contact security@anoma.foundation
contract NativeTokenReceiver is INativeTokenReceiver {
    /// @notice Emits the `NativeTokenDeposited` event to track native token deposits that weren't made via the deposit
    /// method.
    /// @dev This call is bound by the gas limitations for `send`/`transfer` calls introduced by
    /// [ERC-2929](https://eips.ethereum.org/EIPS/eip-2929). Gas cost increases in future hard forks might break this
    /// function.
    receive() external payable override {
        emit NativeTokenReceived({sender: msg.sender, amount: msg.value});
    }
}
