// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std-1.15.0/src/Test.sol";

import {TransientFallbackHandler} from "../src/bases/TransientFallbackHandler.sol";

contract TransientFallbackHandlerTest is Test, TransientFallbackHandler {
    function test_magic_numbers_storage_slot() public pure {
        assertEq(
            _SELECTOR_TO_MAGIC_NUMBERS_MAPPING,
            keccak256(abi.encode(uint256(keccak256("anoma.storage.transient.selectorsToMagicNumbersMapping")) - 1))
                & ~bytes32(uint256(0xff))
        );
    }
}
