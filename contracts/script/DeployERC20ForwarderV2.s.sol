// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";

import {ERC20ForwarderV2} from "../src/drafts/ERC20ForwarderV2.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";

/// @title DeployERC20ForwarderV2
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the ERC20 forwarder v2 contract.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20ForwarderV2 is Script {
    /// @notice Deploys the ERC20 forwarder contract.
    /// @param protocolAdapterV2 The protocol adapter v2 contract that can forward calls.
    /// @param logicRefV2 The reference to the logic function of the resource v2 kind triggering the forward call.
    /// @param emergencyCommittee The emergency committee address that is allowed to set the emergency caller if the
    /// RISC Zero verifier has been stopped.
    /// @param erc20ForwarderV1 The ERC20 forwarder v1 being associated with the stop protocol adapter v1 that funds can
    /// be migrated from.
    function run(address protocolAdapterV2, bytes32 logicRefV2, address emergencyCommittee, address erc20ForwarderV1)
        public
    {
        vm.startBroadcast();
        new ERC20ForwarderV2({
            protocolAdapterV2: protocolAdapterV2,
            logicRefV2: logicRefV2,
            emergencyCommittee: emergencyCommittee,
            erc20ForwarderV1: ERC20Forwarder(erc20ForwarderV1)
        });
        vm.stopBroadcast();
    }
}
