use alloy::primitives::{Address, address};
use alloy_chains::NamedChain;
use std::collections::HashMap;

/// Returns a map of ERC20 forwarder contract deployments for all supported chains.
pub fn erc20_forwarder_deployments_map() -> HashMap<NamedChain, Address> {
    use NamedChain::*;
    HashMap::from([
        (
            Sepolia,
            address!("0x9109d47d17cABF2693cD19de8fAef31875d12aA3"),
        ),
        (
            BaseSepolia,
            address!("0x1ff6a61447F3fD70cAe9C6247663eED90ef25d8c"),
        ),
    ])
}

/// Returns the address of the ERC20 forwarder contract  deployed on the provided chain, if any.
pub fn erc20_forwarder_address(chain: &NamedChain) -> Option<Address> {
    erc20_forwarder_deployments_map().get(chain).cloned()
}
