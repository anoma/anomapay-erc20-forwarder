// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Proxy.sol";
import {Script} from "forge-std-1.16.1/src/Script.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.1/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.1/src/Upgrades.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";

/// @title DeployERC20Forwarder
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the ERC20 forwarder proxy and implementation contract.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20Forwarder is Script {
    /// @notice Deploys the ERC20 forwarder proxy and implementation contract.
    /// @param isTestDeployment Whether the deployment is a test deployment or not. If set to `false`, the ERC20
    /// forwarder proxy and implementation contracts are deployed deterministically.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the logic function of the resource kind triggering the forward call.
    /// @param owner The initial owner of the contract having the upgrade authority.
    function run(bool isTestDeployment, address protocolAdapter, bytes32 logicRef, address owner)
        public
        returns (address proxy, address implementation)
    {
        Options memory opts;
        Upgrades.validateImplementation("ERC20Forwarder.sol:ERC20Forwarder", opts);

        bytes memory initializeCalldata = abi.encodeCall(ERC20Forwarder.initialize, (protocolAdapter, logicRef, owner));

        vm.startBroadcast();

        if (isTestDeployment) {
            implementation = address(new ERC20Forwarder());
            proxy = address(new ERC1967Proxy({implementation: implementation, _data: initializeCalldata}));
        } else {
            implementation = address(new ERC20Forwarder{salt: "ERC20Forwarder"}());
            proxy = address(
                new ERC1967Proxy{salt: "ERC20ForwarderProxy"}({
                    implementation: implementation, _data: initializeCalldata
                })
            );
        }

        vm.stopBroadcast();
    }
}
