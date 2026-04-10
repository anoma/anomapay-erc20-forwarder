#[cfg(test)]
extern crate dotenvy;

use alloy::primitives::{Address, b256};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy_chains::NamedChain;
use anoma_pa_evm_bindings::addresses::protocol_adapter_address;
use anoma_pa_evm_bindings::helpers::alchemy_url;
use anomapay_erc20_forwarder_bindings::addresses::erc20_forwarder_deployments_map;
use anomapay_erc20_forwarder_bindings::contract::erc20_forwarder;
use anomapay_erc20_forwarder_bindings::generated::erc20_forwarder::ERC20Forwarder::ERC20ForwarderInstance;
use std::thread::sleep;
use std::time::Duration;

#[tokio::test]
async fn deployed_forwarders_point_to_the_current_protocol_adapter_contract() {
    // Iterate over all supported chains
    for chain in erc20_forwarder_deployments_map().keys() {
        let fwd_referenced_protocol_adapter: Address = fwd_instance(chain)
            .await
            .getProtocolAdapter()
            .call()
            .await
            .expect("Couldn't get protocol adapter address");

        let deployed_protocol_adapter = protocol_adapter_address(chain).unwrap();

        //  Check that the referenced and deployed protocol adapter addresses match.
        assert_eq!(
            fwd_referenced_protocol_adapter, deployed_protocol_adapter,
            "Protocol adapter address mismatch on network '{chain}'."
        );

        sleep(Duration::from_secs(3));
    }
}

#[tokio::test]
async fn deployed_forwarders_reference_the_expected_logic_ref() {
    // Iterate over all supported chains
    for chain in erc20_forwarder_deployments_map().keys() {
        let actual_logic_ref = fwd_instance(chain)
            .await
            .getLogicRef()
            .call()
            .await
            .expect("Couldn't get logic ref");

        // The token transfer circuit verifying key taken from
        // https://github.com/anoma/anomapay-backend/blob/ec5f9bc0466feb5abf2da5ad7d9a5c365a4d0a8f/simple_transfer/transfer_library/src/lib.rs#L27.
        let expected_logic_ref =
            b256!("0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad");

        // Check that the logic ref in the deployed forwarder matches the expected one from the transfer library.
        assert_eq!(
            actual_logic_ref, expected_logic_ref,
            "Logic address mismatch on network '{chain}': expected {expected_logic_ref}, actual: {actual_logic_ref}."
        );

        sleep(Duration::from_secs(3));
    }
}

async fn fwd_instance(chain: &NamedChain) -> ERC20ForwarderInstance<DynProvider> {
    let rpc_url = alchemy_url(chain).unwrap();

    let provider = ProviderBuilder::new()
        .connect_anvil_with_wallet_and_config(|a| a.fork(rpc_url))
        .expect("Couldn't create anvil provider")
        .erased();
    erc20_forwarder(&provider).await.unwrap()
}
