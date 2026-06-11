#[cfg(test)]
extern crate dotenvy;

use alloy::primitives::{Address, B256};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy_chains::NamedChain;
use anoma_pa_evm_bindings::addresses::protocol_adapter_address;
use anoma_pa_evm_bindings::helpers::alchemy_url;
use anomapay_erc20_forwarder_bindings::addresses::erc20_forwarder_deployments_map;
use anomapay_erc20_forwarder_bindings::contract::erc20_forwarder_proxy;
use anomapay_erc20_forwarder_bindings::generated::erc20_forwarder;
use anomapay_erc20_forwarder_bindings::generated::erc20_forwarder::ERC20Forwarder::ERC20ForwarderInstance;

fn token_transfer_id() -> B256 {
    B256::from_slice(transfer_library::TOKEN_TRANSFER_ID.as_bytes())
}

#[tokio::test]
async fn deployed_forwarders_point_to_the_current_protocol_adapter_contract() {
    // Iterate over all supported chains
    for chain in erc20_forwarder_deployments_map().keys() {
        let fwd_referenced_protocol_adapter: Address = fwd_proxy_instance(chain)
            .await
            .getProtocolAdapter()
            .call()
            .await
            .expect("Couldn't get protocol adapter address");

        let deployed_protocol_adapter = protocol_adapter_address(chain).unwrap();
        println!("{deployed_protocol_adapter}");

        //  Check that the referenced and deployed protocol adapter addresses match.
        assert_eq!(
            fwd_referenced_protocol_adapter, deployed_protocol_adapter,
            "Protocol adapter address mismatch on network '{chain}'."
        );
    }
}

#[tokio::test]
async fn deployed_forwarders_reference_the_expected_logic_ref() {
    // Iterate over all supported chains
    for chain in erc20_forwarder_deployments_map().keys() {
        let actual_logic_ref = fwd_proxy_instance(chain)
            .await
            .getLogicRef()
            .call()
            .await
            .expect("Couldn't get logic ref");

        // Check that the logic ref in the deployed forwarder matches the expected one from the transfer library.
        assert_eq!(
            actual_logic_ref,
            token_transfer_id(),
            "Logic address mismatch on network '{chain}': expected {}, actual: {actual_logic_ref}.",
            token_transfer_id()
        );
    }
}

#[tokio::test]
async fn proxies_point_to_the_deployed_implementation() {
    for (chain, deployment) in erc20_forwarder_deployments_map() {
        let onchain_implementation = fwd_proxy_instance(&chain)
            .await
            .getImplementation()
            .call()
            .await
            .expect("Couldn't get the implementation address");

        // Check that the proxy's implementation matches the one recorded in deployments.json.
        assert_eq!(
            onchain_implementation, deployment.implementation,
            "implementation mismatch on network '{chain}': the proxy points to {onchain_implementation}, but deployments.json records {}.",
            deployment.implementation
        );
    }
}

#[tokio::test]
async fn deployed_implementations_carry_the_expected_version() {
    for (chain, deployment) in erc20_forwarder_deployments_map() {
        let provider = anvil_fork(&chain).await;

        // `getVersion` is `pure`, so it can be read straight from the implementation contract.
        let actual_version =
            erc20_forwarder::ERC20Forwarder::new(deployment.implementation, &provider)
                .getVersion()
                .call()
                .await
                .expect("Couldn't get the deployed implementation version");

        // Deploy the current implementation to read its compiled-in version.
        let expected_version = erc20_forwarder::ERC20Forwarder::deploy(&provider)
            .await
            .expect("Couldn't deploy erc20 forwarder")
            .getVersion()
            .call()
            .await
            .expect("Couldn't get version");

        assert_eq!(
            decode_bytes32_to_utf8(actual_version),
            decode_bytes32_to_utf8(expected_version),
            "ERC20 forwarder implementation version mismatch on network '{chain}'."
        );
    }
}

async fn anvil_fork(chain: &NamedChain) -> DynProvider {
    let rpc_url = alchemy_url(chain).unwrap();

    ProviderBuilder::new()
        .connect_anvil_with_wallet_and_config(|a| a.fork(rpc_url))
        .expect("Couldn't create anvil provider")
        .erased()
}

async fn fwd_proxy_instance(chain: &NamedChain) -> ERC20ForwarderInstance<DynProvider> {
    erc20_forwarder_proxy(&anvil_fork(chain).await)
        .await
        .unwrap()
}

fn decode_bytes32_to_utf8(encoded_string: B256) -> String {
    let bytes = alloy::hex::decode(encoded_string.to_string()).expect("Couldn't decode hex string");

    let trimmed = bytes
        .split(|b| *b == 0)
        .next()
        .expect("No null byte found in bytes");
    str::from_utf8(trimmed)
        .expect("Conversion to UTF-8 failed.")
        .to_string()
}
