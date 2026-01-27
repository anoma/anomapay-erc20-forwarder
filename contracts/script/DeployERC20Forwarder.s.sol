// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IVersion} from "anoma-pa-evm-1.1.0/src/interfaces/IVersion.sol";

import {Script} from "forge-std-1.14.0/src/Script.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {Versioning} from "../src/libs/Versioning.sol";

/// @title DeployERC20Forwarder
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the ERC20 forwarder contract.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20Forwarder is Script {
    /// @notice Deploys the ERC20 forwarder contract.
    /// @param isTestDeployment Whether the deployment is a test deployment or not. If set to `false`, the ERC20
    /// forwarder is deployed deterministically.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the logic function of the resource kind triggering the forward call.
    /// @param emergencyCommittee The emergency committee that can set the emergency caller if the protocol adapter has
    /// been stopped.
    function run(bool isTestDeployment, address protocolAdapter, bytes32 logicRef, address emergencyCommittee)
        public
        returns (address erc20Forwarder)
    {
        vm.startBroadcast();

        if (isTestDeployment) {
            // Deploy regularly.
            erc20Forwarder = address(
                new ERC20Forwarder({
                    protocolAdapter: protocolAdapter, logicRef: logicRef, emergencyCommittee: emergencyCommittee
                })
            );
        } else {
            bytes32 paVersion = IVersion(protocolAdapter).getVersion();

            // Deploy deterministically.
            erc20Forwarder = address(
                new ERC20Forwarder{
                    salt: keccak256(
                        abi.encode("ERC20Forwarder", Versioning._ERC20_FORWARDER_VERSION, "ProtocolAdapter", paVersion)
                    )
                }({
                    protocolAdapter: protocolAdapter, logicRef: logicRef, emergencyCommittee: emergencyCommittee
                })
            );
        }

        vm.stopBroadcast();
    }
}
