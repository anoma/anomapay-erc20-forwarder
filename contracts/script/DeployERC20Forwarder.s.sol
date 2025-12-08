// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Versioning} from "@anoma-evm-pa/libs/Versioning.sol";

import {Script} from "forge-std/Script.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";

/// @title DeployERC20Forwarder
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the ERC20 forwarder contract.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20Forwarder is Script {
    /// @notice Deploys the ERC20 forwarder contract.
    /// @param isTestDeployment Whether the deployment is a test deployment or not. If set to `false`, the ER20
    /// forwarder is deployed deterministically.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the logic function of the resource kind triggering the forward call.
    /// @param emergencyCommittee The emergency committee address that is allowed to set the emergency caller if the
    /// RISC Zero verifier has been stopped.
    function run(bool isTestDeployment, address protocolAdapter, bytes32 logicRef, address emergencyCommittee) public {
        bytes32 salt;
        if (isTestDeployment) {
            salt = bytes32(block.prevrandao);
        } else {
            salt = keccak256(abi.encode("ERC20Forwarder", Versioning._PROTOCOL_ADAPTER_VERSION));
        }

        vm.startBroadcast();
        new ERC20Forwarder{salt: salt}({
            protocolAdapter: protocolAdapter, logicRef: logicRef, emergencyCommittee: emergencyCommittee
        });
        vm.stopBroadcast();
    }
}
