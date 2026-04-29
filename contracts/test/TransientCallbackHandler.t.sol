// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TransientCallbackHandler} from "../src/bases/TransientCallbackHandler.sol";

import {Test} from "forge-std-1.15.0/src/Test.sol";

contract TransientCallbackHandlerTest is Test, TransientCallbackHandler {
    function setUp() public {}

    function test_magic_numbers_storage_slot() public pure {
        assertEq(
            _CALLBACK_MAGIC_NUMBERS_SLOT,
            keccak256(abi.encode(uint256(keccak256("anoma.storage.transient.callbackMagicNumbers")) - 1))
                & ~bytes32(uint256(0xff))
        );
    }
}
