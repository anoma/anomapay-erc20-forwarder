// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1271} from "@openzeppelin-contracts-5.6.1/interfaces/IERC1271.sol";

import {ForwarderBase} from "./bases/ForwarderBase.sol";
import {NativeTokenReceiver} from "./bases/NativeTokenReceiver.sol";
import {TransientFallbackHandler} from "./bases/TransientFallbackHandler.sol";

/// @title ERC20Forwarder
/// @author Anoma Foundation, 2025
/// @notice The ERC20 token forwarder contract allowing to swap ERC20 tokens on a DEX router.
/// @custom:security-contact security@anoma.foundation
contract GenericCallForwarder is IERC1271, ForwarderBase, NativeTokenReceiver, TransientFallbackHandler {
    /// @notice The action struct to be consumed by the DAO's `execute` function resulting in an external call.
    /// @param to The address to call.
    /// @param value The native token value to be sent with the call.
    /// @param data The bytes-encoded function selector and calldata for the call.
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    /// @notice Emitted when calls are executed.
    /// @param calls The array of calls executed.
    /// @param execResults The array with the results of the executed calls.
    event Executed(Call[] calls, bytes[] execResults);

    error CallFailed(uint256 index);

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the logic function of the resource kind triggering the forward call.
    /// been stopped.
    constructor(address protocolAdapter, bytes32 logicRef) ForwarderBase(protocolAdapter, logicRef) {}

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        pure
        override
        returns (bytes4 magicValue)
    {
        (hash, signature);

        // NOTE: Authorization is happening on the resource triggering this call.

        magicValue = IERC1271.isValidSignature.selector;
    }

    /// @notice Forwards a call wrapping or unwrapping ERC20 tokens based on the provided input.
    /// @param input Contains the calls to make.
    /// @return output The empty string signaling that the function call has succeeded.
    // @dev Note: This method is reentrancy-protected by the `nonReentrant` modifier in `ForwarderBase.forwardCall`.
    function _forwardCall(bytes calldata input) internal virtual override returns (bytes memory output) {
        (Call[] memory calls) = abi.decode(input, (Call[]));

        bool success;

        uint256 nCalls = calls.length;
        bytes[] memory execResults = new bytes[](nCalls);

        for (uint256 i = 0; i < nCalls;) {
            (success, execResults[i]) = calls[i].to.call{value: calls[i].value}(calls[i].data);

            require(success, CallFailed({index: i}));

            unchecked {
                ++i;
            }
        }

        emit Executed({calls: calls, execResults: execResults});

        output = "";
    }
}
