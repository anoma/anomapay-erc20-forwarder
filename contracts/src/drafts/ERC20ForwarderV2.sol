// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Forwarder} from "../ERC20Forwarder.sol";

/// @title ERC20ForwarderV2
/// @author Anoma Foundation, 2025
/// @notice A draft second version of the ERC20 forwarder used to exercise the UUPS upgrade path.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from ERC20Forwarder
contract ERC20ForwarderV2 is ERC20Forwarder {
    /// @notice Initializes a freshly deployed V2 proxy at storage version 2.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the ERC20 resource logic function triggering the forward calls.
    /// @param initialOwner The initial owner of the contract having the upgrade authority.
    function initialize( /* solhint-disable-line comprehensive-interface*/
        address protocolAdapter,
        bytes32 logicRef,
        address initialOwner
    )
        external
        override
        reinitializer(2)
    {
        __ForwarderBaseUpgradeable_init({
            protocolAdapter: protocolAdapter, logicRef: logicRef, initialOwner: initialOwner
        });
    }

    /// @notice Reinitializes an existing proxy when upgrading it from V1 to V2.
    /// @param logicRefV2 The reference to the ERC20 resource logic function v2 triggering the forward calls.
    function reinitialize( /* solhint-disable-line comprehensive-interface */
        bytes32 logicRefV2
    )
        external
        reinitializer(2)
    {
        ForwarderBaseStorage storage $ = _getForwarderBaseStorage();
        $._logicRef = logicRefV2;
    }
}
