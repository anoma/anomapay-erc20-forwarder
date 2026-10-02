// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// forge-lint: disable-next-item(literal-instead-of-constant)
/// @title RecordedDeployments
/// @author Anoma Foundation, 2026
/// @notice The ERC20 forwarder proxies each environment records, and the V1 forwarders the chains ran before them.
/// @dev Generated from `crates/bindings/deployments.json`, the single source of truth, which the bindings crate
/// embeds and checks against the chains. Do not edit by hand: run `just contracts-gen`, which CI reruns
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
        deployments = new Deployment[](0);
    }

    /// @notice Returns the deployments the production environment records.
    /// @return deployments The recorded production deployments.
    function production() internal pure returns (Deployment[] memory deployments) {
        deployments = new Deployment[](0);
    }

    /// @notice Returns the V1 ERC20 forwarders, one per chain that ran a v1 protocol adapter.
    /// @return forwarders The recorded V1 forwarders.
    function v1() internal pure returns (V1Forwarder[] memory forwarders) {
        forwarders = new V1Forwarder[](10);
        forwarders[0] = V1Forwarder({
            chainId: 11155111,
            forwarder: 0x0A62bE41E66841f693f922991C4e40C89cb0CFDF,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[1] = V1Forwarder({
            chainId: 1,
            forwarder: 0x775C81A47F2618a8594a7a7f4A3Df2a300337559,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[2] = V1Forwarder({
            chainId: 84532,
            forwarder: 0xfAa9DE773Be11fc759A16F294d32BB2261bF818B,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[3] = V1Forwarder({
            chainId: 8453,
            forwarder: 0xfAa9DE773Be11fc759A16F294d32BB2261bF818B,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[4] = V1Forwarder({
            chainId: 10,
            forwarder: 0xfAa9DE773Be11fc759A16F294d32BB2261bF818B,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[5] = V1Forwarder({
            chainId: 42161,
            forwarder: 0xfAa9DE773Be11fc759A16F294d32BB2261bF818B,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[6] = V1Forwarder({
            chainId: 56,
            forwarder: 0xDe6A308ed57AF26BFf059e6C550BD4908aC1840e,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[7] = V1Forwarder({
            chainId: 143,
            forwarder: 0x23dc44E1a1c3d5432EeC8A1c027e22ccDC0A8F54,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[8] = V1Forwarder({
            chainId: 988,
            forwarder: 0x334E41aA1df8f521E3cC64b5fa19b666b8251CDC,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
        forwarders[9] = V1Forwarder({
            chainId: 4326,
            forwarder: 0x334E41aA1df8f521E3cC64b5fa19b666b8251CDC,
            logicRef: 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad
        });
    }
}
