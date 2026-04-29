// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SlotDerivation} from "@openzeppelin-contracts-5.6.1/utils/SlotDerivation.sol";
import {TransientSlot} from "@openzeppelin-contracts-5.6.1/utils/TransientSlot.sol";

import {ICallbackHandler} from "../interfaces/ICallbackHandler.sol";

/// @title TransientCallbackHandler
/// @author Anoma Foundation, 2026
/// @notice A base contract for handling callbacks by transiently registering a magic number together with the callback
/// function's selector.
/// @dev This contract provides the `_handleCallback` function that inheriting contracts have to call inside their
/// `fallback()` function. This allows to adaptively register ERC standards that conduct callbacks, e.g.,
/// * ERC-721: Non-Fungible Token Standard (https://eips.ethereum.org/EIPS/eip-721)
/// * ERC-1155: Multi Token Standard (https://eips.ethereum.org/EIPS/eip-1155)
/// * ERC-165: Standard Interface Detection (https://eips.ethereum.org/EIPS/eip-165)
/// that require a magic number to be returned via an associated callback function.
abstract contract TransientCallbackHandler is ICallbackHandler {
    using SlotDerivation for bytes32;
    using TransientSlot for bytes32;
    using TransientSlot for TransientSlot.Bytes32Slot;

    /// @notice The ERC-7201 (see https://eips.ethereum.org/EIPS/eip-7201) storage location of the transient mapping
    /// between callback selectors and magic numbers.
    /// @dev Obtained from `keccak256(abi.encode(uint256(keccak256("anoma.transient.callbackMagicNumbers")) - 1)) & ~bytes32(uint256(0xff))`.
    bytes32 internal constant _CALLBACK_MAGIC_NUMBERS_SLOT =
        0x1dae74dd10e2457c24ce9c2801f2181050f9946aca5d39fefd0bdb1ea627da00;

    /// @notice The magic number referring to unregistered callbacks.
    bytes4 internal constant _UNREGISTERED_CALLBACK = bytes4(0);

    /// @notice Thrown if the callback function is not registered.
    /// @param callbackSelector The selector of the callback function.
    /// @param magicNumber The magic number to be registered for the callback function selector.
    error UnregisteredCallback(bytes4 callbackSelector, bytes4 magicNumber);

    /// @inheritdoc ICallbackHandler
    function registerCallback(bytes4 callbackSelector, bytes4 magicNumber) external {
        _CALLBACK_MAGIC_NUMBERS_SLOT.deriveMapping(bytes32(callbackSelector)).asBytes32().tstore(bytes32(magicNumber));
    }

    /// @notice Handles callbacks to adaptively support ERC standards.
    /// @dev This function is supposed to be called via `_handleCallback(msg.sig, msg.data)` in the `fallback()` function of the inheriting contract.
    /// @param callbackSelector The function selector of the callback function.
    /// @param data The calldata.
    /// @return magicNumber The magic number registered for the function selector triggering the fallback.
    function _handleCallback(bytes4 callbackSelector, bytes memory data) internal returns (bytes4 magicNumber) {
        magicNumber = bytes4(_CALLBACK_MAGIC_NUMBERS_SLOT.deriveMapping(bytes32(callbackSelector)).asBytes32().tload());

        require(
            magicNumber != _UNREGISTERED_CALLBACK,
            UnregisteredCallback({callbackSelector: callbackSelector, magicNumber: magicNumber})
        );

        emit CallbackReceived({sender: msg.sender, sig: callbackSelector, data: data});
    }
}
