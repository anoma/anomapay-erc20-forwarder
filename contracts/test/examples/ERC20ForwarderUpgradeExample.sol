// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";

/// @title ERC20ForwarderUpgradeExample
/// @author Anoma Foundation, 2025
/// @notice A draft second version of the ERC20 forwarder used to exercise the UUPS upgrade path.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from ERC20Forwarder
contract ERC20ForwarderUpgradeExample is ERC20Forwarder {
    /// @notice The initializer version of this implementation, one more than that of `ERC20Forwarder`.
    uint64 public constant REINITIALIZER_VERSION = _REINITIALIZER_VERSION + 1;

    /// @inheritdoc ERC20Forwarder
    /// @dev The upgrade safety validation requires each implementation to define an initializer.
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

    /// @notice Replaces the accepted logic ref. Only the owner can call it, at most once for each implementation.
    /// @param newLogicRef The logic ref that the forwarder accepts after the call.
    /// @dev Repeats the body of `ERC20Forwarder.reinitializeLogicRef` at `REINITIALIZER_VERSION`.
    function reinitializeLogicRef( /* solhint-disable-line comprehensive-interface */
        bytes32 newLogicRef
    )
        external
        override
        onlyOwner
        reinitializer(REINITIALIZER_VERSION)
    {
        require(newLogicRef != bytes32(0), ZeroLogicRefNotAllowed());

        ForwarderBaseStorage storage $ = _getForwarderBaseStorage();
        _checkLogicRefNotDenied({protocolAdapter: $._protocolAdapter, logicRef: newLogicRef});
        $._logicRef = newLogicRef;
    }
}
