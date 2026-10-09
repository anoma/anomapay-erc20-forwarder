// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";

/// @notice The implementation of a second incident: the draft with the next reinitializer version.
contract EmergencyMigratingERC20ForwarderNextMock is EmergencyMigratingERC20Forwarder {
    constructor(address forwarderV1) EmergencyMigratingERC20Forwarder(forwarderV1) {}

    function reinitialize(bytes32 newLogicRef, bytes32[] calldata vulnerableLogicRefs)
        external
        override
        onlyOwner
        reinitializer(3)
    {
        _reinitialize({newLogicRef: newLogicRef, vulnerableLogicRefs: vulnerableLogicRefs});
    }
}
