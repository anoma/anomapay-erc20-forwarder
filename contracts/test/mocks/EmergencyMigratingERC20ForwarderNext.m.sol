// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EnumerableSet} from "@openzeppelin-contracts-5.7.0/utils/structs/EnumerableSet.sol";

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";

/// @notice The implementation of a second incident: the draft with the next reinitializer version.
contract EmergencyMigratingERC20ForwarderNextMock is EmergencyMigratingERC20Forwarder {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    constructor(address forwarderV1) EmergencyMigratingERC20Forwarder(forwarderV1) {}

    /// @dev Repeats the body of `EmergencyMigratingERC20Forwarder.reinitialize`, which runs only at version 2.
    function reinitialize(bytes32 newLogicRef, bytes32[] calldata vulnerableLogicRefs)
        external
        override
        onlyOwner
        reinitializer(3)
    {
        // Check the arguments.
        require(newLogicRef != bytes32(0), ZeroLogicRefNotAllowed());
        uint256 vulnerableCount = vulnerableLogicRefs.length;
        require(vulnerableCount != 0, EmptyVulnerableLogicRefList());

        // Check that the adapter denies the new logic reference on neither denylist.
        ForwarderBaseStorage storage $ = _getForwarderBaseStorage();
        address protocolAdapter = $._protocolAdapter;
        _checkLogicRefNotDenied({protocolAdapter: protocolAdapter, logicRef: newLogicRef});

        // Check and list each vulnerable logic reference.
        EnumerableSet.Bytes32Set storage listed = _getEmergencyMigratingERC20ForwarderStorage()._vulnerableLogicRefs;
        for (uint256 i = 0; i < vulnerableCount; ++i) {
            bytes32 vulnerableLogicRef = vulnerableLogicRefs[i];
            _checkLogicRefDenied({protocolAdapter: protocolAdapter, logicRef: vulnerableLogicRef});
            require(listed.add(vulnerableLogicRef), LogicRefAlreadyVulnerable(vulnerableLogicRef));

            emit VulnerableLogicRefListed(vulnerableLogicRef);
        }

        // Replace the logic reference if the new one differs.
        bytes32 previousLogicRef = $._logicRef;
        if (newLogicRef != previousLogicRef) {
            $._logicRef = newLogicRef;

            emit LogicRefReplaced({previousLogicRef: previousLogicRef, newLogicRef: newLogicRef});
        }
    }
}
