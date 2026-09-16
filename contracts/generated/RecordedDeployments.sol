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
        Deployment[] memory deployments = isProduction ? production() : staging();

        for (uint256 i = 0; i < deployments.length; ++i) {
            if (deployments[i].chainId == chainId) {
                return true;
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
        deployments = new Deployment[](2);
        deployments[0] = Deployment({
            chainId: 11155111,
            proxy: Proxy({
                addr: 0x997FA4eDA52748eA313f429B61223faBBca49C9b,
                initialImplementation: 0x34F2B89c2a9362349615a0d61Da9e754fa54b9C5,
                initializerData: hex"d26b3e6e000000000000000000000000e23d3b3fc0944cb0c1184c6e04b9d26ed50cec51bc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad00000000000000000000000061462be56782568376f9cb069382efa72764a407",
                creationCode: hex"6080604052610284803803806100148161016e565b9283398101604082820312610156578151916001600160a01b03831690818403610156576020810151906001600160401b038211610156570182601f82011215610156578051906001600160401b03821161015a5761007c601f8301601f191660200161016e565b938285526020838301011161015657815f9260208093018387015e8401015281511561014757823b15610135577f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc80546001600160a01b031916821790557fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b5f80a280511561011e5761010e91610193565b505b604051606490816102208239f35b505034156101105763b398979f60e01b5f5260045ffd5b634c9c8ce360e01b5f5260045260245ffd5b6330a289cf60e21b5f5260045ffd5b5f80fd5b634e487b7160e01b5f52604160045260245ffd5b6040519190601f01601f191682016001600160401b0381118382101761015a57604052565b905f8091602081519101845af4808061020c575b156101c75750506040513d81523d5f602083013e60203d82010160405290565b156101ec57639996b31560e01b5f9081526001600160a01b0391909116600452602490fd5b3d156101fd576040513d5f823e3d90fd5b63d6bda27560e01b5f5260045ffd5b503d1515806101a75750813b15156101a756fe60806040525f8073ffffffffffffffffffffffffffffffffffffffff7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5416368280378136915af43d5f803e156053573d5ff35b3d5ffdfea164736f6c6343000824000a"
            })
        });
        deployments[1] = Deployment({
            chainId: 84532,
            proxy: Proxy({
                addr: 0xE54182d915dE447deFc4A17Ec1D4E0dc627551F7,
                initialImplementation: 0x34F2B89c2a9362349615a0d61Da9e754fa54b9C5,
                initializerData: hex"d26b3e6e000000000000000000000000b5a5a52af29da0c8801d9caf4d75a4d6c3895f0abc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad00000000000000000000000061462be56782568376f9cb069382efa72764a407",
                creationCode: hex"6080604052610284803803806100148161016e565b9283398101604082820312610156578151916001600160a01b03831690818403610156576020810151906001600160401b038211610156570182601f82011215610156578051906001600160401b03821161015a5761007c601f8301601f191660200161016e565b938285526020838301011161015657815f9260208093018387015e8401015281511561014757823b15610135577f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc80546001600160a01b031916821790557fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b5f80a280511561011e5761010e91610193565b505b604051606490816102208239f35b505034156101105763b398979f60e01b5f5260045ffd5b634c9c8ce360e01b5f5260045260245ffd5b6330a289cf60e21b5f5260045ffd5b5f80fd5b634e487b7160e01b5f52604160045260245ffd5b6040519190601f01601f191682016001600160401b0381118382101761015a57604052565b905f8091602081519101845af4808061020c575b156101c75750506040513d81523d5f602083013e60203d82010160405290565b156101ec57639996b31560e01b5f9081526001600160a01b0391909116600452602490fd5b3d156101fd576040513d5f823e3d90fd5b63d6bda27560e01b5f5260045ffd5b503d1515806101a75750813b15156101a756fe60806040525f8073ffffffffffffffffffffffffffffffffffffffff7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5416368280378136915af43d5f803e156053573d5ff35b3d5ffdfea164736f6c6343000824000a"
            })
        });
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
