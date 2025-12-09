use alloy::primitives::{Address, address};
use alloy_chains::NamedChain;
use std::collections::HashMap;

/// Returns a map of ERC20 forwarder contract deployments for all supported chains.
pub fn erc20_forwarder_deployments_map() -> HashMap<NamedChain, Address> {
    use NamedChain::*;
    HashMap::from([(
        Sepolia,
        address!("0x8E9bB084EE344e619D31fC5D3A0f123a2c80C0B2"),
    )])
}

/// Returns the address of the ERC20 forwarder contract  deployed on the provided chain, if any.
pub fn erc20_forwarder_address(chain: &NamedChain) -> Option<Address> {
    erc20_forwarder_deployments_map().get(chain).cloned()
}
