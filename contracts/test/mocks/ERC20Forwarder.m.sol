// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice A stand-in for the V2 ERC20 forwarder proxy, answering the two getters the migration script reads it
/// through. It holds the custody the migration moves, so it needs code and nothing else.
contract ERC20ForwarderMock {
    address internal immutable _OWNER;
    address internal immutable _PROTOCOL_ADAPTER;

    constructor(address owner_, address protocolAdapter) {
        _OWNER = owner_;
        _PROTOCOL_ADAPTER = protocolAdapter;
    }

    function owner() external view returns (address account) {
        account = _OWNER;
    }

    function getProtocolAdapter() external view returns (address protocolAdapter) {
        protocolAdapter = _PROTOCOL_ADAPTER;
    }
}
