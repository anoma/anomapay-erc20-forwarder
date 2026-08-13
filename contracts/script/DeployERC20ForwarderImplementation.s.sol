// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.1/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.1/src/Upgrades.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";

/// @title DeployERC20ForwarderImplementation
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the ERC20 forwarder implementation contract.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20ForwarderImplementation is Script {
    /// @notice The CREATE2 salt for the deterministic implementation deployment.
    bytes32 public constant IMPLEMENTATION_SALT = "ERC20Forwarder";

    /// @notice Validates the ERC20 forwarder implementation for upgrade safety and deploys it.
    /// @param isTestDeployment Whether the deployment is a test deployment or not. If set to `false`, the
    /// implementation is deployed deterministically.
    /// @return implementation The ERC20 forwarder implementation contract — the contract to verify on block
    /// explorers, which carries the source.
    function run(bool isTestDeployment) public returns (address implementation) {
        Options memory opts;
        Upgrades.validateImplementation("ERC20Forwarder.sol:ERC20Forwarder", opts);

        vm.startBroadcast();
        if (isTestDeployment) {
            implementation = address(new ERC20Forwarder());
        } else {
            implementation = address(new ERC20Forwarder{salt: IMPLEMENTATION_SALT}());
        }
        vm.stopBroadcast();
    }
}
