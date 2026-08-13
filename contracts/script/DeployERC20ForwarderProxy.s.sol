// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Proxy.sol";
import {Script} from "forge-std-1.16.1/src/Script.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {DeployERC20ForwarderImplementation} from "./DeployERC20ForwarderImplementation.s.sol";

/// @title DeployERC20ForwarderProxy
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the ERC20 forwarder implementation and an ERC-1967 proxy pointing to it.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20ForwarderProxy is Script {
    /// @notice The CREATE2 salt for the deterministic proxy deployment.
    bytes32 public constant PROXY_SALT = "ERC20ForwarderProxy";

    /// @notice Deploys the ERC20 forwarder implementation and an ERC-1967 proxy pointing to it. The implementation is
    /// validated for upgrade safety in both cases.
    /// @param isTestDeployment Whether the deployment is a test deployment or not. If set to `false`, the ERC20
    /// forwarder proxy and implementation contracts are deployed deterministically.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the logic function of the resource kind triggering the forward call.
    /// @param owner The initial owner of the contract having the upgrade authority.
    /// @return proxy The ERC20 forwarder proxy contract to interact with.
    /// @return implementation The ERC20 forwarder implementation contract the proxy delegates to — the contract to
    /// verify on block explorers, which carries the source, whereas the proxy carries the ERC-1967 bytecode.
    function run(bool isTestDeployment, address protocolAdapter, bytes32 logicRef, address owner)
        public
        returns (address proxy, address implementation)
    {
        implementation = new DeployERC20ForwarderImplementation().run(isTestDeployment);

        bytes memory initializeCalldata = abi.encodeCall(ERC20Forwarder.initialize, (protocolAdapter, logicRef, owner));

        vm.startBroadcast();
        if (isTestDeployment) {
            proxy = address(new ERC1967Proxy({implementation: implementation, _data: initializeCalldata}));
        } else {
            proxy = address(
                new ERC1967Proxy{salt: PROXY_SALT}({implementation: implementation, _data: initializeCalldata})
            );
        }
        vm.stopBroadcast();
    }
}
