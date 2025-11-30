// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Address} from "@openzeppelin-contracts/utils/Address.sol";

import {ProtocolAdapterSpecificForwarderBase} from "../../src/bases/ProtocolAdapterSpecificForwarderBase.sol";
import {ForwarderTargetExample} from "./ForwarderTarget.e.sol";

contract ForwarderExample is ProtocolAdapterSpecificForwarderBase {
    using Address for address;

    address public immutable TARGET;

    event CallForwarded(bytes input, bytes output);
    event EmergencyCallForwarded(bytes input, bytes output);

    constructor(address protocolAdapter, bytes32 calldataCarrierLogicRef)
        ProtocolAdapterSpecificForwarderBase(protocolAdapter, calldataCarrierLogicRef)
    {
        TARGET = address(new ForwarderTargetExample());
    }

    function _forwardCall(bytes calldata input) internal override returns (bytes memory output) {
        output = TARGET.functionCall(input);

        emit CallForwarded({input: input, output: output});
    }
}
