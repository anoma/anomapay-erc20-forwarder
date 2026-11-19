// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";

/// @title ERC20ForwarderUpgradeExample
/// @author Anoma Foundation, 2025
/// @notice A draft second version of the ERC20 forwarder used to exercise the UUPS upgrade path.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from ERC20Forwarder
contract ERC20ForwarderUpgradeExample is ERC20Forwarder {
    /// @inheritdoc ERC20Forwarder
    /// @dev The upgrade safety validation rejects an implementation without its own initializer.
    function initialize( /* solhint-disable-line comprehensive-interface*/
        address protocolAdapter,
        bytes32 logicRef,
        address initialOwner
    )
        external
        override
        initializer
    {
        __ForwarderBaseUpgradeable_init({
            protocolAdapter: protocolAdapter, logicRef: logicRef, initialOwner: initialOwner
        });
    }

    /// @notice Reinitializes an existing proxy when it is upgraded to this implementation. Only the owner can call it.
    /// @param upgradedLogicRef The logic ref that this implementation accepts.
    function reinitialize( /* solhint-disable-line comprehensive-interface */
        bytes32 upgradedLogicRef
    )
        external
        onlyOwner
        reinitializer(2)
    {
        ForwarderBaseStorage storage $ = _getForwarderBaseStorage();
        $._logicRef = upgradedLogicRef;
    }
}
