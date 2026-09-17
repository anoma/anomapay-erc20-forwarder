// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.7.0/proxy/ERC1967/ERC1967Proxy.sol";
import {Script} from "forge-std-1.16.2/src/Script.sol";

import {RecordedDeployments} from "../generated/RecordedDeployments.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {DeployERC20ForwarderImplementation} from "./DeployERC20ForwarderImplementation.s.sol";
import {Parameters} from "./Parameters.sol";

/// @title DeployERC20ForwarderProxy
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the ERC20 forwarder implementation and an ERC-1967 proxy pointing to it on supported
/// networks.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20ForwarderProxy is Script {
    /// @notice The CREATE2 salt for the staging environment proxy deployment.
    bytes32 public constant PROXY_SALT_STAGING = Parameters.PROXY_SALT_STAGING;

    /// @notice The CREATE2 salt for the production environment proxy deployment.
    bytes32 public constant PROXY_SALT_PRODUCTION = Parameters.PROXY_SALT_PRODUCTION;

    /// @notice The staging environment proxy owner — the deployment wallet, upgrading instantly.
    address public constant PROXY_OWNER_STAGING = Parameters.DEPLOYMENT_WALLET;

    /// @notice The production environment proxy owner — the Safe multisig queueing upgrades.
    address public constant PROXY_OWNER_PRODUCTION = Parameters.FWD_MULTISIG;

    /// @notice Thrown if the environment already has a deployment recorded for this chain.
    error DeploymentAlreadyRecorded(string environment, uint256 chainId);

    /// @notice Thrown if the proxy of this source version is already deployed.
    error ProxyAlreadyDeployed(address proxy);

    /// @notice Deploys an ERC-1967 proxy pointing to the ERC20 forwarder implementation deterministically. The
    /// implementation is validated for upgrade safety and deployed first, unless the other environment deployed it
    /// already.
    /// @param isProduction Whether to deploy the production or the staging environment proxy, selecting the CREATE2
    /// salt and the owner receiving the authority to authorize upgrades.
    /// @param protocolAdapter The protocol adapter proxy of the same environment, the only caller allowed to forward
    /// calls.
    /// @param logicRef The reference to the ERC20 resource logic function triggering the forward calls.
    /// @return proxy The ERC20 forwarder proxy contract to interact with.
    /// @return implementation The ERC20 forwarder implementation contract the proxy delegates to.
    /// @return initializerData The proxy constructor's initializer data, to record in `deployments.json`.
    /// @return creationCode The ERC-1967 proxy creation code, to record in `deployments.json`.
    function run(bool isProduction, address protocolAdapter, bytes32 logicRef)
        public
        returns (address proxy, address implementation, bytes memory initializerData, bytes memory creationCode)
    {
        DeployERC20ForwarderImplementation implementationDeployScript = new DeployERC20ForwarderImplementation();

        bytes32 salt = isProduction ? PROXY_SALT_PRODUCTION : PROXY_SALT_STAGING;

        // Checks
        {
            require(
                !RecordedDeployments.isRecorded({isProduction: isProduction, chainId: block.chainid}),
                DeploymentAlreadyRecorded(environmentName(isProduction), block.chainid)
            );

            implementation = implementationDeployScript.predict();

            (proxy, initializerData, creationCode) = _predict({
                salt: salt,
                implementation: implementation,
                protocolAdapter: protocolAdapter,
                logicRef: logicRef,
                isProduction: isProduction
            });
            require(proxy.code.length == 0, ProxyAlreadyDeployed({proxy: proxy}));
        }

        // Deployment
        if (implementation.code.length == 0) {
            implementationDeployScript.run();
        }

        vm.startBroadcast();
        proxy = address(new ERC1967Proxy{salt: salt}({implementation: implementation, _data: initializerData}));
        vm.stopBroadcast();
    }

    /// @notice Predicts the deterministic address the proxy of this source version deploys to.
    /// @param isProduction Whether to predict the production or the staging environment proxy.
    /// @param protocolAdapter The protocol adapter proxy of the same environment.
    /// @param logicRef The reference to the ERC20 resource logic function triggering the forward calls.
    /// @return proxy The predicted ERC20 forwarder proxy contract address.
    /// @return implementation The predicted implementation contract address the proxy commits to.
    function predict(bool isProduction, address protocolAdapter, bytes32 logicRef)
        public
        returns (address proxy, address implementation)
    {
        bytes32 salt = isProduction ? PROXY_SALT_PRODUCTION : PROXY_SALT_STAGING;

        implementation = new DeployERC20ForwarderImplementation().predict();

        (proxy,,) = _predict({
            salt: salt,
            implementation: implementation,
            protocolAdapter: protocolAdapter,
            logicRef: logicRef,
            isProduction: isProduction
        });
    }

    /// @notice Returns the name of an environment, which keys its deployments in `deployments.json`.
    /// @param isProduction Whether to name the production or the staging environment.
    /// @return name The environment name.
    function environmentName(bool isProduction) public pure returns (string memory name) {
        name = isProduction ? "production" : "staging";
    }

    /// @notice Derives the deterministic proxy address and the constructor arguments it commits to.
    /// @param salt The CREATE2 salt of the environment.
    /// @param implementation The implementation contract the proxy delegates to.
    /// @param protocolAdapter The protocol adapter proxy of the same environment.
    /// @param logicRef The reference to the ERC20 resource logic function triggering the forward calls.
    /// @param isProduction Whether to derive the production or the staging environment proxy, selecting the owner.
    /// @return proxy The deterministic ERC20 forwarder proxy contract address.
    /// @return initializerData The proxy constructor's initializer data.
    /// @return creationCode The ERC-1967 proxy creation code.
    function _predict(
        bytes32 salt,
        address implementation,
        address protocolAdapter,
        bytes32 logicRef,
        bool isProduction
    ) internal pure returns (address proxy, bytes memory initializerData, bytes memory creationCode) {
        initializerData = abi.encodeCall(
            ERC20Forwarder.initialize,
            (protocolAdapter, logicRef, isProduction ? PROXY_OWNER_PRODUCTION : PROXY_OWNER_STAGING)
        );
        creationCode = type(ERC1967Proxy).creationCode;

        bytes memory constructorArgs = abi.encode(implementation, initializerData);

        bytes memory initCode = abi.encodePacked(creationCode, constructorArgs);

        proxy = vm.computeCreate2Address({salt: salt, initCodeHash: keccak256(initCode)});
    }
}
