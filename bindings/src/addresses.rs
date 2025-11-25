use alloy::primitives::Address;
use alloy_chains::NamedChain;
use std::collections::HashMap;

/// Returns a map of ERC20 forwarder contract deployments for all supported chains.
pub fn erc20_forwarder_deployments_map() -> HashMap<NamedChain, Address> {
    HashMap::from([])
}

/// Returns the address of the ERC20 forwarder contract  deployed on the provided chain, if any.
pub fn erc20_forwarder_address(chain: &NamedChain) -> Option<Address> {
    erc20_forwarder_deployments_map().get(chain).cloned()
}
