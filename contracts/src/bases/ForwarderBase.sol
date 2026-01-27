// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.5.0/utils/ReentrancyGuardTransient.sol";
import {IForwarder} from "anoma-pa-evm-1.1.0/src/interfaces/IForwarder.sol";
import {IVersion} from "anoma-pa-evm-1.1.0/src/interfaces/IVersion.sol";

import {ILogicRefSpecific} from "../interfaces/ILogicRefSpecific.sol";
import {IProtocolAdapterSpecific} from "../interfaces/IProtocolAdapterSpecific.sol";
import {Versioning} from "../libs/Versioning.sol";

/// @title ForwarderBase
/// @author Anoma Foundation, 2025
/// @notice A base contract for a protocol-adapter- and logic-reference-specific forwarder contract.
/// @custom:security-contact security@anoma.foundation
abstract contract ForwarderBase is
    IForwarder,
    IVersion,
    IProtocolAdapterSpecific,
    ILogicRefSpecific,
    ReentrancyGuardTransient
{
    /// @notice The protocol adapter contract that can forward calls.
    address internal immutable _PROTOCOL_ADAPTER;

    /// @notice The reference to the logic function of the resource kind triggering the forward calls.
    bytes32 internal immutable _LOGIC_REF;

    error ZeroNotAllowed();
    error UnauthorizedCaller(address expected, address actual);
    error UnauthorizedLogicRef(bytes32 expected, bytes32 actual);

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the logic function of the resource kind triggering the forward call.
    constructor(address protocolAdapter, bytes32 logicRef) {
        if (protocolAdapter == address(0) || logicRef == bytes32(0)) {
            revert ZeroNotAllowed();
        }

        _PROTOCOL_ADAPTER = protocolAdapter;

        _LOGIC_REF = logicRef;
    }

    /// @inheritdoc IForwarder
    function forwardCall(bytes32 logicRef, bytes calldata input) external nonReentrant returns (bytes memory output) {
        _checkCaller(_PROTOCOL_ADAPTER);

        if (_LOGIC_REF != logicRef) {
            revert UnauthorizedLogicRef({expected: _LOGIC_REF, actual: logicRef});
        }

        output = _forwardCall(input);
    }

    /// @inheritdoc IProtocolAdapterSpecific
    function getProtocolAdapter() external view override returns (address protocolAdapter) {
        protocolAdapter = _PROTOCOL_ADAPTER;
    }

    /// @inheritdoc ILogicRefSpecific
    function getLogicRef() external view override returns (bytes32 logicRef) {
        logicRef = _LOGIC_REF;
    }

    /// @inheritdoc IVersion
    function getVersion() external pure returns (bytes32 version) {
        version = Versioning._ERC20_FORWARDER_VERSION;
    }

    // slither-disable-start unimplemented-functions

    /// @notice Forwards calls.
    /// @param input The `bytes` encoded input of the call.
    /// @return output The `bytes` encoded output of the call.
    function _forwardCall(bytes calldata input) internal virtual returns (bytes memory output);

    // slither-disable-end unimplemented-functions

    /// @notice Checks that an expected caller is calling the function and reverts otherwise.
    /// @param expected The expected caller.
    function _checkCaller(address expected) internal view {
        if (msg.sender != expected) {
            revert UnauthorizedCaller({expected: expected, actual: msg.sender});
        }
    }
}
