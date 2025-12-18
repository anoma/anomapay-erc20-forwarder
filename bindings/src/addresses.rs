use alloy::primitives::{Address, address};
use alloy_chains::NamedChain;
use std::collections::HashMap;

/// Returns a map of ERC20 forwarder contract deployments for all supported chains.
pub fn erc20_forwarder_deployments_map() -> HashMap<NamedChain, Address> {
    use NamedChain::*;
    HashMap::from([
        (
            Sepolia,
            address!("0x9bbC75f66f5344864FfABCF70625B99E42e5F108"),
        ),
        (
            BaseSepolia,
            address!("0xfeE5b48919100c192E017992810c9539ebD00249"),
        ),
        (Base, address!("0xfeE5b48919100c192E017992810c9539ebD00249")),
    ])
}

/// Returns the address of the ERC20 forwarder contract  deployed on the provided chain, if any.
pub fn erc20_forwarder_address(chain: &NamedChain) -> Option<Address> {
    erc20_forwarder_deployments_map().get(chain).cloned()
}
