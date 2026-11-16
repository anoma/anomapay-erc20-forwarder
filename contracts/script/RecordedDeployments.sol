// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeploymentRecords} from "./DeploymentRecords.sol";

/// @title RecordedDeployments
/// @author Anoma Foundation, 2026
/// @notice Reads the ERC20 forwarder proxies each environment records, and the legacy ERC20 forwarders the chains ran
/// before them, from `crates/bindings/deployments.json`.
/// @dev The file is the only record. The bindings crate embeds it and checks it against the chains.
/// @custom:security-contact security@anoma.foundation
library RecordedDeployments {
    /// @notice A recorded ERC20 forwarder proxy. The field `addr` holds the address, which is a reserved word.
    /// @dev The genesis fields pin how the address was derived: the creation code and the constructor arguments
    /// determine it together with the environment salt, and none of them can be read from the chain once the proxy is
    /// upgraded. The fields follow the alphabetical order of their keys, in which `parseJson` encodes them.
    struct Proxy {
        address addr;
        bytes creationCode;
        address initialImplementation;
        bytes initializerData;
    }

    /// @notice A recorded ERC20 forwarder deployment.
    struct Deployment {
        uint256 chainId;
        Proxy proxy;
    }

    /// @notice The directory of the bindings package that holds the records, relative to the project root.
    string internal constant _DIRECTORY = "../crates/bindings";

    /// @notice The name of the bindings package.
    string internal constant _PACKAGE_NAME = "anomapay-erc20-forwarder-bindings";

    /// @notice Returns whether the environment records a deployment for the chain.
    /// @param isProduction Whether to check the production or the staging environment.
    /// @param chainId The chain ID to look for.
    /// @return recorded Whether the environment records a deployment for the chain.
    function isRecorded(bool isProduction, uint256 chainId) internal view returns (bool recorded) {
        recorded = forwarderProxy({isProduction: isProduction, chainId: chainId}) != address(0);
    }

    /// @notice Returns the ERC20 forwarder proxy an environment records for a chain.
    /// @param isProduction Whether to read the production or the staging environment.
    /// @param chainId The chain ID to look for.
    /// @return proxy The recorded proxy, or the zero address if the environment records none for the chain.
    function forwarderProxy(bool isProduction, uint256 chainId) internal view returns (address proxy) {
        proxy = DeploymentRecords.addressOf({
            json: _records(), key: DeploymentRecords.environment(isProduction), chainId: chainId, field: "proxy.address"
        });
    }

    /// @notice Returns the legacy ERC20 forwarder of a chain.
    /// @param chainId The chain ID to look for.
    /// @return forwarder The legacy ERC20 forwarder, or the zero address if the chain ran none.
    function legacyForwarder(uint256 chainId) internal view returns (address forwarder) {
        forwarder = DeploymentRecords.addressOf({json: _records(), key: "legacy", chainId: chainId, field: "forwarder"});
    }

    /// @notice Returns the deployments the staging environment records.
    /// @return deployments The recorded staging deployments.
    function staging() internal view returns (Deployment[] memory deployments) {
        deployments = _deployments({isProduction: false});
    }

    /// @notice Returns the deployments the production environment records.
    /// @return deployments The recorded production deployments.
    function production() internal view returns (Deployment[] memory deployments) {
        deployments = _deployments({isProduction: true});
    }

    /// @notice Returns the deployments an environment records.
    /// @param isProduction Whether to return the production or the staging environment.
    /// @return deployments The recorded deployments.
    function _deployments(bool isProduction) private view returns (Deployment[] memory deployments) {
        bytes memory encoded =
            DeploymentRecords.entries({json: _records(), key: DeploymentRecords.environment(isProduction)});
        deployments = abi.decode(encoded, (Deployment[]));
    }

    /// @notice Returns the content of the records file.
    /// @return json The JSON text of the file.
    function _records() private view returns (string memory json) {
        json = DeploymentRecords.read({directory: _DIRECTORY, packageName: _PACKAGE_NAME});
    }
}
