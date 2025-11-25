#[cfg(test)]
extern crate dotenv;

use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy_chains::NamedChain;
use erc20_forwarder_bindings::addresses::erc20_forwarder_deployments_map;
use erc20_forwarder_bindings::contract::ERC20Forwarder::ERC20ForwarderInstance;
use erc20_forwarder_bindings::contract::erc20_forwarder;
use evm_protocol_adapter_bindings::addresses::protocol_adapter_address;
use evm_protocol_adapter_bindings::helpers::alchemy_url;

#[tokio::test]
async fn versions_of_deployed_forwarders_point_to_the_current_protocol_adapter_contract() {
    // Iterate over all supported chains
    for chain in erc20_forwarder_deployments_map().keys() {
        let fwd_referenced_protocol_adapter: alloy::primitives::Address = fwd_instance(chain)
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
    }
}

async fn fwd_instance(chain: &NamedChain) -> ERC20ForwarderInstance<DynProvider> {
    let rpc_url = alchemy_url(chain).unwrap();

    let provider = ProviderBuilder::new()
        .connect_anvil_with_wallet_and_config(|a| a.fork(rpc_url))
        .expect("Couldn't create anvil provider")
        .erased();
    erc20_forwarder(provider).await.unwrap()
}
