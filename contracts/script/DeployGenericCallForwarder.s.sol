// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IVersion} from "anoma-pa-evm-1.2.0-rc.0/src/interfaces/IVersion.sol";

import {Script} from "forge-std-1.15.0/src/Script.sol";

import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";
import {Versioning} from "../src/libs/Versioning.sol";

/// @title contract DeployGenericCallForwarder is Script {
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the generic call forwarder contract.
/// @custom:security-contact security@anoma.foundation
contract DeployGenericCallForwarder is Script {
    function run(address protocolAdapter, bytes32 logicRef) public returns (address erc20Forwarder) {
        vm.startBroadcast();

        erc20Forwarder = address(new GenericCallForwarder({protocolAdapter: protocolAdapter, logicRef: logicRef}));

        vm.stopBroadcast();
    }
}
