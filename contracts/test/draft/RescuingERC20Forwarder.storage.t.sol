// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SlotDerivation} from "@openzeppelin-contracts-5.7.0/utils/SlotDerivation.sol";
import {Test} from "forge-std-1.16.2/src/Test.sol";

import {RescuingERC20Forwarder} from "../../src/draft/RescuingERC20Forwarder.sol";

contract RescuingERC20ForwarderStorageTest is Test, RescuingERC20Forwarder {
    function test_storage_slot() public pure {
        assertEq(
            _RESCUING_ERC20_FORWARDER_STORAGE_SLOT, SlotDerivation.erc7201Slot("anoma.storage.RescuingERC20Forwarder")
        );
    }
}
