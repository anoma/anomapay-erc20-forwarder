// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {IProtocolAdapterSpecific} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IProtocolAdapterSpecific.sol";

import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ProtocolAdapterMock} from "./ProtocolAdapter.m.sol";

/// @notice A stand-in for the deployed V1 ERC20 forwarder, holding the custody the migration moves. It keeps the
/// guards the deployed contract applies: the committee assigns the emergency caller once, only that caller forwards,
/// and both need the protocol adapter stopped.
contract ERC20ForwarderV1Mock is IEmergencyMigratable, IProtocolAdapterSpecific {
    address internal immutable _PROTOCOL_ADAPTER;
    address internal immutable _EMERGENCY_COMMITTEE;

    address internal _emergencyCaller;

    error EmergencyCallerNotSet();
    error UnauthorizedCaller(address expected, address actual);
    error EmergencyCallerAlreadySet(address emergencyCaller);
    error ProtocolAdapterNotStopped();
    error UnexpectedCallType(ERC20Forwarder.CallType callType);

    constructor(address protocolAdapter, address emergencyCommittee) {
        _PROTOCOL_ADAPTER = protocolAdapter;
        _EMERGENCY_COMMITTEE = emergencyCommittee;
    }

    /// @inheritdoc IEmergencyMigratable
    function forwardEmergencyCall(bytes calldata input) external returns (bytes memory output) {
        require(_emergencyCaller != address(0), EmergencyCallerNotSet());
        _checkCaller(_emergencyCaller);
        _checkEmergencyStopped();

        (ERC20Forwarder.CallType callType, IERC20 token, uint128 amount, address receiver) =
            abi.decode(input, (ERC20Forwarder.CallType, IERC20, uint128, address));
        require(callType == ERC20Forwarder.CallType.Unwrap, UnexpectedCallType(callType));

        SafeERC20.safeTransfer(token, receiver, amount);
        output = "";
    }

    /// @inheritdoc IEmergencyMigratable
    function setEmergencyCaller(address newEmergencyCaller) external {
        _checkCaller(_EMERGENCY_COMMITTEE);
        require(_emergencyCaller == address(0), EmergencyCallerAlreadySet(_emergencyCaller));
        _checkEmergencyStopped();

        _emergencyCaller = newEmergencyCaller;
    }

    /// @inheritdoc IEmergencyMigratable
    function getEmergencyCaller() external view returns (address caller) {
        caller = _emergencyCaller;
    }

    /// @inheritdoc IProtocolAdapterSpecific
    function getProtocolAdapter() external view returns (address protocolAdapter) {
        protocolAdapter = _PROTOCOL_ADAPTER;
    }

    function _checkCaller(address expected) internal view {
        require(msg.sender == expected, UnauthorizedCaller({expected: expected, actual: msg.sender}));
    }

    function _checkEmergencyStopped() internal view {
        require(ProtocolAdapterMock(_PROTOCOL_ADAPTER).isEmergencyStopped(), ProtocolAdapterNotStopped());
    }
}
