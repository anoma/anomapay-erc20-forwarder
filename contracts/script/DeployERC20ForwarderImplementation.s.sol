// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.2/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";

/// @title DeployERC20ForwarderImplementation
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the ERC20 forwarder implementation.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20ForwarderImplementation is Script {
    /// @notice The CREATE2 salt for the implementation deployment, shared by the staging and production environments.
    bytes32 public constant IMPLEMENTATION_SALT = "ERC20ForwarderImpl";

    /// @notice The initialization data to pass to `upgradeToAndCall` when upgrading a proxy to this implementation —
    /// empty because the current version requires no reinitialization.
    bytes public constant INITIALIZATION_DATA = "";

    /// @notice Thrown if the implementation of the current source version is not deployed yet.
    error ImplementationNotDeployed(address implementation);

    /// @notice Thrown if the implementation of the current source version is already deployed.
    error ImplementationAlreadyDeployed(address implementation);

    /// @notice Thrown if an implementation to upgrade to is not the one the current source version deploys to.
    error UnexpectedImplementation(address expected, address actual);

    /// @notice Validates the ERC20 forwarder implementation for upgrade safety and deploys it.
    /// @return implementation The ERC20 forwarder implementation contract — the contract to verify on block
    /// explorers, which carries the source.
    function run() public returns (address implementation) {
        implementation = predict();
        require(implementation.code.length == 0, ImplementationAlreadyDeployed({implementation: implementation}));

        Options memory opts;
        Upgrades.validateImplementation("ERC20Forwarder.sol:ERC20Forwarder", opts);

        vm.startBroadcast();
        implementation = address(new ERC20Forwarder{salt: IMPLEMENTATION_SALT}());
        vm.stopBroadcast();
    }

    /// @notice Predicts the deterministic address the implementation of this source version deploys to. The
    /// constructor takes no arguments, so the address is the same on every chain.
    /// @return implementation The predicted implementation contract address.
    function predict() public pure returns (address implementation) {
        implementation = vm.computeCreate2Address({
            salt: IMPLEMENTATION_SALT, initCodeHash: keccak256(type(ERC20Forwarder).creationCode)
        });
    }
}
