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
    for chain in erc20_forwarder_deployments_map().keys() {
        // Skip chains not yet registered in pa-evm bindings
        let Some(deployed_protocol_adapter) = protocol_adapter_address(chain) else {
            eprintln!("Skipping '{chain}': no protocol adapter address in pa-evm bindings yet.");
            continue;
        };

        let Some(fwd) = try_fwd_instance(chain).await else {
            continue;
        };

        let fwd_referenced_protocol_adapter: Address = fwd
            .getProtocolAdapter()
            .call()
            .await
            .expect("Couldn't get protocol adapter address");

        assert_eq!(
            fwd_referenced_protocol_adapter, deployed_protocol_adapter,
            "Protocol adapter address mismatch on network '{chain}'."
        );

        sleep(Duration::from_secs(3));
    }
}

#[tokio::test]
async fn deployed_forwarders_reference_the_expected_logic_ref() {
    for chain in erc20_forwarder_deployments_map().keys() {
        // Skip chains not yet registered in pa-evm bindings
        if protocol_adapter_address(chain).is_none() {
            eprintln!("Skipping '{chain}': no protocol adapter address in pa-evm bindings yet.");
            continue;
        }

        let Some(fwd) = try_fwd_instance(chain).await else {
            continue;
        };

        let actual_logic_ref = fwd
            .getLogicRef()
            .call()
            .await
            .expect("Couldn't get logic ref");

        // The token transfer circuit verifying key taken from
        // https://github.com/anoma/anomapay-backend/blob/ec5f9bc0466feb5abf2da5ad7d9a5c365a4d0a8f/simple_transfer/transfer_library/src/lib.rs#L27.
        let expected_logic_ref =
            b256!("0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad");

        assert_eq!(
            actual_logic_ref, expected_logic_ref,
            "Logic address mismatch on network '{chain}': expected {expected_logic_ref}, actual: {actual_logic_ref}."
        );

        sleep(Duration::from_secs(3));
    }
}

/// Tries to create an ERC20Forwarder instance for the given chain.
/// Returns None for chains without Alchemy RPC support, logging a skip message.
async fn try_fwd_instance(chain: &NamedChain) -> Option<ERC20ForwarderInstance<DynProvider>> {
    let rpc_url = match alchemy_url(chain) {
        Ok(url) => url,
        Err(_) => {
            eprintln!("Skipping '{chain}': no Alchemy RPC URL available.");
            return None;
        }
    };

    let provider = ProviderBuilder::new()
        .connect_anvil_with_wallet_and_config(|a| a.fork(rpc_url))
        .expect("Couldn't create anvil provider")
        .erased();
    Some(erc20_forwarder(&provider).await.unwrap())
}
