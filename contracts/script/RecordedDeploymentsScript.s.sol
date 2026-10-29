// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.17.0/src/Script.sol";

import {RecordedDeployments} from "../generated/RecordedDeployments.sol";
import {DeployERC20ForwarderImplementation} from "./DeployERC20ForwarderImplementation.s.sol";
import {DeployERC20ForwarderProxy} from "./DeployERC20ForwarderProxy.s.sol";

/// @title RecordedDeploymentsScript
/// @author Anoma Foundation, 2026
/// @notice The base of the scripts that act on a recorded ERC20 forwarder proxy. The records name the proxy and this
/// source predicts the implementation, so `--rpc-url` alone names the chain.
/// @custom:security-contact security@anoma.foundation
abstract contract RecordedDeploymentsScript is Script {
    /// @notice Thrown if the environment records no ERC20 forwarder for the chain.
    error DeploymentNotRecorded(string environment, uint256 chainId);

    /// @notice Returns the ERC20 forwarder the environment records for the chain `--rpc-url` names, and reverts unless
    /// it is recorded.
    /// @param isProduction Whether to read the production or the staging ERC20 forwarder.
    /// @return proxy The recorded ERC20 forwarder proxy.
    function _requireRecordedProxy(bool isProduction) internal returns (address proxy) {
        proxy = _recordedProxy(isProduction);
        if (proxy == address(0)) {
            // A `require` would create the script on every call: it evaluates the error arguments first.
            revert DeploymentNotRecorded(new DeployERC20ForwarderProxy().environmentName(isProduction), block.chainid);
        }
    }

    /// @notice Returns the implementation of this source version, and reverts unless it is deployed.
    /// @param implementationDeployScript The script that predicts the implementation's deterministic address.
    /// @return implementation The deployed implementation.
    function _requireDeployedImplementation(DeployERC20ForwarderImplementation implementationDeployScript)
        internal
        view
        returns (address implementation)
    {
        implementation = implementationDeployScript.predict();
        require(
            implementation.code.length != 0,
            DeployERC20ForwarderImplementation.ImplementationNotDeployed(implementation)
        );
    }

    /// @notice Returns the ERC20 forwarder the environment records for the chain `--rpc-url` names.
    /// @param isProduction Whether to read the production or the staging ERC20 forwarder.
    /// @return proxy The recorded ERC20 forwarder proxy, or the zero address if the environment records none for the
    /// chain.
    function _recordedProxy(bool isProduction) internal view virtual returns (address proxy) {
        proxy = RecordedDeployments.forwarderProxy({isProduction: isProduction, chainId: block.chainid});
    }
}
