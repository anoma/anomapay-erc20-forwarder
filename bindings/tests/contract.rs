#[cfg(test)]
extern crate dotenvy;

use alloy::primitives::{Address, B256, b256};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy_chains::NamedChain;
use anoma_pa_evm_bindings::addresses::protocol_adapter_address;
use anoma_pa_evm_bindings::generated::protocol_adapter::ProtocolAdapter::ProtocolAdapterInstance;
use anoma_pa_evm_bindings::helpers::alchemy_url;
use anomapay_erc20_forwarder_bindings::addresses::erc20_forwarder_deployments_map;
use anomapay_erc20_forwarder_bindings::contract::erc20_forwarder;
use anomapay_erc20_forwarder_bindings::generated::erc20_forwarder;
use anomapay_erc20_forwarder_bindings::generated::erc20_forwarder::ERC20Forwarder::ERC20ForwarderInstance;

// The token transfer circuit verifying key taken from
// https://github.com/anoma/anomapay-backend/blob/ec5f9bc0466feb5abf2da5ad7d9a5c365a4d0a8f/simple_transfer/transfer_library/src/lib.rs#L27.
const TOKEN_TRANSFER_CIRCUIT_ID: B256 =
    b256!("0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad");

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
        let actual_logic_ref = fwd_instance(chain)
            .await
            .getLogicRef()
            .call()
            .await
            .expect("Couldn't get logic ref");

        // Check that the logic ref in the deployed forwarder matches the expected one from the transfer library.
        assert_eq!(
            actual_logic_ref, TOKEN_TRANSFER_CIRCUIT_ID,
            "Logic address mismatch on network '{chain}': expected {TOKEN_TRANSFER_CIRCUIT_ID}, actual: {actual_logic_ref}."
        );
    }
}

#[tokio::test]
async fn versions_of_deployed_forwarders_match_the_expected_version() {
    // Iterate over all supported chains
    for chain in erc20_forwarder_deployments_map().keys() {
        let existing_fwd = fwd_instance(chain).await;

        let existing_pa_address = existing_fwd
            .getProtocolAdapter()
            .call()
            .await
            .expect("Couldn't get protocol adapter");

        let existing_pa_owner =
            ProtocolAdapterInstance::new(existing_pa_address, existing_fwd.provider().clone())
                .owner()
                .call()
                .await
                .expect("Couldn't get PA owner");

        let current_fwd = erc20_forwarder::ERC20Forwarder::deploy(
            existing_fwd.provider(),
            existing_pa_address,
            TOKEN_TRANSFER_CIRCUIT_ID,
            existing_pa_owner,
        )
        .await
        .expect("Couldn't deploy erc20 forwarder");

        let expected_version = current_fwd
            .getVersion()
            .call()
            .await
            .expect("Couldn't get version");

        let actual_version: alloy::primitives::FixedBytes<32> = existing_fwd
            .getVersion()
            .call()
            .await
            .expect("Couldn't get protocol adapter version");

        //  Check that the deployed ERC20 forwarder version matches the expected version.
        assert_eq!(
            decode_bytes32_to_utf8(actual_version),
            decode_bytes32_to_utf8(expected_version),
            "ERC20 forwarder version mismatch on network '{chain}'."
        );
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
