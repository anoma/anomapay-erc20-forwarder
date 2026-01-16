use alloy::primitives::{Address, address};
use alloy_chains::NamedChain;
use std::collections::HashMap;

/// Returns a map of ERC20 forwarder contract deployments for all supported chains.
pub fn erc20_forwarder_deployments_map() -> HashMap<NamedChain, Address> {
    HashMap::from([
        (
            NamedChain::Sepolia,
            address!("0xa04942494174eD85A11416E716262eC0AE0a065d"),
        ),
        (
            NamedChain::Mainnet,
            address!("0x0D38C332135f9f0de4dcc4a6F9c918b72e2A1Df3"),
        ),
        (
            NamedChain::BaseSepolia,
            address!("0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"),
        ),
        (
            NamedChain::Base,
            address!("0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"),
        ),
        (
            NamedChain::Optimism,
            address!("0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"),
        ),
        (
            NamedChain::Arbitrum,
            address!("0xA73Ce304460F17C3530b58BA95bCD3B89Bd38D69"),
        ),
    ])
}

/// Returns the address of the ERC20 forwarder contract  deployed on the provided chain, if any.
pub fn erc20_forwarder_address(chain: &NamedChain) -> Option<Address> {
    erc20_forwarder_deployments_map().get(chain).cloned()
}
