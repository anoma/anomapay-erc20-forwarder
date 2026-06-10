// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.1/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.1/src/Upgrades.sol";

import {ERC20ForwarderV2} from "../src/drafts/ERC20ForwarderV2.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";

/// @title UpgradeERC20Forwarder
/// @author Anoma Foundation, 2025
/// @notice A script to upgrade the ERC20 forwarder UUPS proxy to a new implementation.
/// @custom:security-contact security@anoma.foundation
contract UpgradeERC20Forwarder is Script {
    /// @notice Deploys the new implementation deterministically and upgrades the ERC20 forwarder proxy to it.
    /// @param isTestDeployment Whether the deployment is a test deployment or not. If set to `false`, the new ERC20
    /// forwarder implementation contract is deployed deterministically.
    /// @param erc20ForwarderProxy The address of the deployed ERC20 forwarder proxy to upgrade.
    /// @param logicRefV2 The reference to the ERC20 resource logic function v2 triggering the forward calls.
    function run(bool isTestDeployment, address erc20ForwarderProxy, bytes32 logicRefV2) public {
        Options memory opts;
        opts.referenceContract = "ERC20Forwarder.sol:ERC20Forwarder";
        Upgrades.validateUpgrade("ERC20ForwarderV2.sol:ERC20ForwarderV2", opts);

        bytes memory reinitializeCalldata = abi.encodeCall(ERC20ForwarderV2.reinitialize, (logicRefV2));

        vm.startBroadcast();

        address newImplementation;

        if (isTestDeployment) {
            newImplementation = address(new ERC20ForwarderV2());
        } else {
            newImplementation = address(new ERC20ForwarderV2{salt: "ERC20ForwarderV2"}());
        }

        ERC20Forwarder(erc20ForwarderProxy)
            .upgradeToAndCall({newImplementation: newImplementation, data: reinitializeCalldata});

        vm.stopBroadcast();
    }
}
