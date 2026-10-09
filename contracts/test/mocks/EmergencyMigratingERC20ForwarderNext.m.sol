// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";

/// @notice The implementation of a later incident: the draft with a higher reinitializer version.
contract EmergencyMigratingERC20ForwarderNextMock is EmergencyMigratingERC20Forwarder {
    uint64 internal immutable _VERSION;

    constructor(uint64 version, address forwarderV1) EmergencyMigratingERC20Forwarder(forwarderV1) {
        _VERSION = version;
    }

    function reinitialize(bytes32 newLogicRef, bytes32[] calldata vulnerableLogicRefs)
        external
        override
        onlyOwner
        reinitializer(_VERSION)
    {
        _reinitialize({newLogicRef: newLogicRef, vulnerableLogicRefs: vulnerableLogicRefs});
    }
}
