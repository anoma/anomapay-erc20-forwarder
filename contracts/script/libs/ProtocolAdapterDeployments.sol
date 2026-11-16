// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeploymentsJson} from "./DeploymentsJson.sol";

/// @title ProtocolAdapterDeployments
/// @author Anoma Foundation, 2026
/// @notice Reads the protocol adapter proxies each environment records, and the legacy protocol adapters, from the
/// `deployments.json` file of the pa-evm bindings release that `foundry.toml` depends on.
/// @custom:security-contact security@anoma.foundation
library ProtocolAdapterDeployments {
    /// @notice The directory of the bindings package that holds the records, relative to the project root.
    string internal constant _DIRECTORY = "dependencies/anoma-pa-evm-bindings-3.0.0-rc.22/crates/bindings";

    /// @notice The name of the bindings package.
    string internal constant _PACKAGE_NAME = "anoma-pa-evm-bindings";

    /// @notice Returns the protocol adapter proxy an environment records for a chain.
    /// @param isProduction Whether to read the production or the staging environment.
    /// @param chainId The chain ID to look for.
    /// @return proxy The recorded proxy, or the zero address if the environment records none for the chain.
    function protocolAdapterProxy(bool isProduction, uint256 chainId) internal view returns (address proxy) {
        proxy = DeploymentsJson.addressOf({
            json: _records(), key: DeploymentsJson.environment(isProduction), chainId: chainId, field: "proxy.address"
        });
    }

    /// @notice Returns the legacy protocol adapter of a chain.
    /// @param chainId The chain ID to look for.
    /// @return protocolAdapter The legacy protocol adapter, or the zero address if the chain ran none.
    function legacyProtocolAdapter(uint256 chainId) internal view returns (address protocolAdapter) {
        protocolAdapter =
            DeploymentsJson.addressOf({json: _records(), key: "legacy", chainId: chainId, field: "protocolAdapter"});
    }

    /// @notice Returns the content of the records file.
    /// @return json The JSON text of the file.
    function _records() private view returns (string memory json) {
        json = DeploymentsJson.read({directory: _DIRECTORY, packageName: _PACKAGE_NAME});
    }
}
