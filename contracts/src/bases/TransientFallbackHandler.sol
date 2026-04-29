// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SlotDerivation} from "@openzeppelin-contracts-5.6.1/utils/SlotDerivation.sol";
import {TransientSlot} from "@openzeppelin-contracts-5.6.1/utils/TransientSlot.sol";

import {IFallbackHandler} from "../interfaces/IFallbackHandler.sol";

/// @title TransientFallbackHandler
/// @author Anoma Foundation, 2026
/// @notice A base contract for handling fallbacks by transiently registering a magic number together with the calling
/// function's selector.
/// @dev This contract provides the `_handleFallback` function that inheriting contracts have to call inside their
/// `fallback()` function. This allows to adaptively register ERC standards that conduct callbacks, e.g.,
/// * ERC-721: Non-Fungible Token Standard (https://eips.ethereum.org/EIPS/eip-721)
/// * ERC-1155: Multi Token Standard (https://eips.ethereum.org/EIPS/eip-1155)
/// * ERC-165: Standard Interface Detection (https://eips.ethereum.org/EIPS/eip-165)
/// that require a magic number to be returned via an associated callback function.
abstract contract TransientFallbackHandler is IFallbackHandler {
    using SlotDerivation for bytes32;
    using TransientSlot for bytes32;
    using TransientSlot for TransientSlot.Bytes32Slot;

    /// @notice The ERC-7201 (see https://eips.ethereum.org/EIPS/eip-7201) storage location of the transient mapping
    /// between callback selectors and magic numbers.
    /// @dev Obtained from
    // solhint-disable-next-line max-line-length
    /// keccak256(abi.encode(uint256(keccak256("anoma.transient.selectorsToMagicNumbersMapping")) - 1)) & ~bytes32(uint256(0xff)).
    bytes32 internal constant _SELECTOR_TO_MAGIC_NUMBERS_MAPPING =
        0x01253fac32f5e751b951b222de7ecaceaacff877d50c81f3faa99e9c47e1ac00;

    /// @notice The magic number referring to unregistered callbacks.
    bytes4 internal constant _UNREGISTERED_CALLBACK = bytes4(0);

    /// @notice Thrown if the selector of a calling function is not registered.
    /// @param selector The selector of the calling function.
    /// @param magicNumber The magic number to be registered for the callback function selector.
    error UnregisteredSelector(bytes4 selector, bytes4 magicNumber);

    /// @notice The fallback function being able handle different ERC standards by responding to registered function
    /// selectors with magic numbers.
    /// @param data An alias being equivalent to `msg.data`. This feature of the fallback function was introduced with
    /// the solidity compiler version 0.7.6 (see https://github.com/ethereum/solidity/releases/tag/v0.7.6).
    /// @return magicNumber The bytes-encoded magic number registered for the selector of the function selector
    /// that is triggering the fallback.
    fallback(bytes calldata data) external returns (bytes memory magicNumber) {
        magicNumber = abi.encode(_handleFallback(msg.sig, data));
    }

    /// @inheritdoc IFallbackHandler
    function registerSelector(bytes4 selector, bytes4 magicNumber) external {
        _SELECTOR_TO_MAGIC_NUMBERS_MAPPING.deriveMapping(bytes32(selector)).asBytes32().tstore(bytes32(magicNumber));
    }

    /// @notice Handles callbacks to adaptively support ERC standards.
    /// @dev This function is supposed to be called via `_handleFallback(msg.sig, msg.data)` in the `fallback()`
    /// function of the inheriting contract.
    /// @param selector The function selector of the callback function.
    /// @param data The calldata.
    /// @return magicNumber The magic number registered for the function selector triggering the fallback.
    function _handleFallback(bytes4 selector, bytes memory data) internal returns (bytes4 magicNumber) {
        magicNumber = bytes4(_SELECTOR_TO_MAGIC_NUMBERS_MAPPING.deriveMapping(bytes32(selector)).asBytes32().tload());

        require(
            magicNumber != _UNREGISTERED_CALLBACK, UnregisteredSelector({selector: selector, magicNumber: magicNumber})
        );

        emit FallbackHandled({sender: msg.sender, selector: selector, data: data});
    }
}
