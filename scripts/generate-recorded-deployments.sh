#!/usr/bin/env bash
# Generates the Solidity mirror of the recorded ERC20 forwarder deployments.
#
# Reads the deployment records, the single source of truth, and writes them as a
# library the contracts package can read without leaving its own directory. Run
# it through `just contracts-gen-deployments`; CI reruns it and fails on a diff.
#
# The records store checksummed addresses, which Solidity address literals
# require. A wrong checksum fails the bindings tests and the contract build, so
# this script passes them through unchanged. Chains that share a deployment
# repeat its address, so the library disables the `literal-instead-of-constant`
# lint.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
records="${root}/crates/bindings/deployments.json"
output="${root}/contracts/generated/RecordedDeployments.sol"

# Emits the statements that fill the `deployments` array of one environment.
entries() {
    jq --exit-status --raw-output --arg environment "$1" '
        .[$environment] as $records
        | "        deployments = new Deployment[](\($records | length));",
          ( $records
            | to_entries[]
            | "        deployments[\(.key)] = Deployment({",
              "            chainId: \(.value.chainId),",
              "            proxy: Proxy({",
              "                addr: \(.value.proxy.address),",
              "                initialImplementation: \(.value.proxy.initialImplementation),",
              "                initializerData: hex\"\(.value.proxy.initializerData[2:])\",",
              "                creationCode: hex\"\(.value.proxy.creationCode[2:])\"",
              "            })",
              "        });"
          )
    ' "$records"
}

# Emits the statements that fill the `forwarders` array of the V1 forwarders.
v1_entries() {
    jq --exit-status --raw-output '
        .v1 as $records
        | "        forwarders = new V1Forwarder[](\($records | length));",
          ( $records
            | to_entries[]
            | "        forwarders[\(.key)] = V1Forwarder({",
              "            chainId: \(.value.chainId),",
              "            forwarder: \(.value.forwarder),",
              "            logicRef: \(.value.logicRef)",
              "        });"
          )
    ' "$records"
}

mkdir -p "$(dirname "$output")"

{
    cat <<'SOLIDITY'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// forge-lint: disable-next-item(literal-instead-of-constant)
/// @title RecordedDeployments
/// @author Anoma Foundation, 2026
/// @notice The ERC20 forwarder proxies each environment records, and the V1 forwarders the chains ran before them.
/// @dev Generated from `crates/bindings/deployments.json`, the single source of truth, which the bindings crate
/// embeds and checks against the chains. Do not edit by hand: run `just contracts-gen-deployments`, which CI reruns
/// and fails on any diff. The records live with the bindings because that crate publishes them; this library carries
/// them into Solidity so the contracts package reads nothing outside itself.
/// @custom:security-contact security@anoma.foundation
library RecordedDeployments {
    /// @notice A recorded ERC20 forwarder proxy. The field `addr` holds the address, which is a reserved word.
    /// @dev The genesis fields pin how the address was derived: the creation code and the constructor arguments
    /// determine it together with the environment salt, and none of them can be read from the chain once the proxy is
    /// upgraded.
    struct Proxy {
        address addr;
        address initialImplementation;
        bytes initializerData;
        bytes creationCode;
    }

    /// @notice A recorded ERC20 forwarder deployment.
    struct Deployment {
        uint256 chainId;
        Proxy proxy;
    }

    /// @notice The immutable ERC20 forwarder that ran with a chain's v1 protocol adapter, and the logic ref it
    /// accepts. It belongs to no environment.
    struct V1Forwarder {
        uint256 chainId;
        address forwarder;
        bytes32 logicRef;
    }

    /// @notice Returns whether the environment records a deployment for the chain.
    /// @param isProduction Whether to check the production or the staging environment.
    /// @param chainId The chain ID to look for.
    /// @return recorded Whether the environment records a deployment for the chain.
    function isRecorded(bool isProduction, uint256 chainId) internal pure returns (bool recorded) {
        recorded = forwarderProxy({isProduction: isProduction, chainId: chainId}) != address(0);
    }

    /// @notice Returns the ERC20 forwarder proxy an environment records for a chain.
    /// @param isProduction Whether to read the production or the staging environment.
    /// @param chainId The chain ID to look for.
    /// @return proxy The recorded proxy, or the zero address if the environment records none for the chain.
    function forwarderProxy(bool isProduction, uint256 chainId) internal pure returns (address proxy) {
        Deployment[] memory deployments = isProduction ? production() : staging();

        for (uint256 i = 0; i < deployments.length; ++i) {
            if (deployments[i].chainId == chainId) {
                return deployments[i].proxy.addr;
            }
        }
    }

    /// @notice Returns the V1 ERC20 forwarder of a chain.
    /// @param chainId The chain ID to look for.
    /// @return forwarder The V1 forwarder, or the zero address if the chain ran none.
    function forwarderV1(uint256 chainId) internal pure returns (address forwarder) {
        V1Forwarder[] memory forwarders = v1();

        for (uint256 i = 0; i < forwarders.length; ++i) {
            if (forwarders[i].chainId == chainId) {
                return forwarders[i].forwarder;
            }
        }
    }

    /// @notice Returns the deployments the staging environment records.
    /// @return deployments The recorded staging deployments.
    function staging() internal pure returns (Deployment[] memory deployments) {
SOLIDITY

    entries staging

    cat <<'SOLIDITY'
    }

    /// @notice Returns the deployments the production environment records.
    /// @return deployments The recorded production deployments.
    function production() internal pure returns (Deployment[] memory deployments) {
SOLIDITY

    entries production

    cat <<'SOLIDITY'
    }

    /// @notice Returns the V1 ERC20 forwarders, one per chain that ran a v1 protocol adapter.
    /// @return forwarders The recorded V1 forwarders.
    function v1() internal pure returns (V1Forwarder[] memory forwarders) {
SOLIDITY

    v1_entries

    cat <<'SOLIDITY'
    }
}
SOLIDITY
} >"$output"

(cd "${root}/contracts" && forge fmt generated/RecordedDeployments.sol)

echo "generated ${output}"
