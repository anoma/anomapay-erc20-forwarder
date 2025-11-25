use alloy::primitives::Address;
use alloy_chains::NamedChain;
use std::collections::HashMap;

/// Returns a map of protocol adapter deployments for all supported chains.
pub fn forwarder_deployments_map() -> HashMap<NamedChain, Address> {
    HashMap::from([])
}

/// Returns the address of the protocol adapter deployed on the provided chain, if any.
pub fn forwarder_address(chain: &NamedChain) -> Option<Address> {
    forwarder_deployments_map().get(chain).cloned()
}
