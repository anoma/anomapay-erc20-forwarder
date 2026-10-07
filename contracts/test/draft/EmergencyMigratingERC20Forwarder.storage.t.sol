// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SlotDerivation} from "@openzeppelin-contracts-5.7.0/utils/SlotDerivation.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";

contract EmergencyMigratingERC20ForwarderStorageTest is Test, EmergencyMigratingERC20Forwarder {
    function test_storage_slot() public pure {
        assertEq(
            _EMERGENCY_MIGRATING_ERC20_FORWARDER_STORAGE_SLOT,
            SlotDerivation.erc7201Slot("anoma.storage.EmergencyMigratingERC20Forwarder")
        );
    }
}
