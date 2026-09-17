// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployERC20ForwarderProxy} from "../../script/DeployERC20ForwarderProxy.s.sol";

/// @notice The proxy deploy script, forwarding for the given protocol adapter instead of the recorded one. The records
/// are compiled in, so they name no test deployment.
contract DeployERC20ForwarderProxyMock is DeployERC20ForwarderProxy {
    address internal immutable _PROTOCOL_ADAPTER;

    constructor(address protocolAdapter) {
        _PROTOCOL_ADAPTER = protocolAdapter;
    }

    function _protocolAdapter(bool) internal view override returns (address protocolAdapter) {
        protocolAdapter = _PROTOCOL_ADAPTER;
    }
}
