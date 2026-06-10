use alloy::primitives::Address;
use alloy_chains::NamedChain;
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::LazyLock;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeploymentEntry {
    chain_id: u64,
    proxy: String,
    implementation: String,
}

/// A deployed ERC20 forwarder: the `proxy` that users interact with and the `implementation` it delegates to.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Erc20ForwarderDeployment {
    /// The ERC1967 proxy address users interact with.
    pub proxy: Address,
    /// The implementation (logic) contract the proxy delegates to.
    pub implementation: Address,
}

static DEPLOYMENTS: LazyLock<HashMap<NamedChain, Erc20ForwarderDeployment>> = LazyLock::new(|| {
    let entries: Vec<DeploymentEntry> = serde_json::from_str(include_str!("../deployments.json"))
        .expect("deployments.json: invalid JSON");

    entries
        .into_iter()
        .filter_map(|e| {
            let chain = NamedChain::try_from(e.chain_id).ok()?;
            let proxy: Address = e.proxy.parse().ok()?;
            let implementation: Address = e.implementation.parse().ok()?;
            Some((
                chain,
                Erc20ForwarderDeployment {
                    proxy,
                    implementation,
                },
            ))
        })
        .collect()
});

/// Returns a map of ERC20 forwarder deployments for all supported chains.
pub fn erc20_forwarder_deployments_map() -> HashMap<NamedChain, Erc20ForwarderDeployment> {
    DEPLOYMENTS.clone()
}

/// Returns the ERC20 forwarder proxy address deployed on the provided chain, if any.
///
/// This is the address users interact with.
pub fn erc20_forwarder_proxy_address(chain: &NamedChain) -> Option<Address> {
    DEPLOYMENTS.get(chain).map(|d| d.proxy)
}

/// Returns the ERC20 forwarder implementation address deployed on the provided chain, if any.
pub fn erc20_forwarder_implementation_address(chain: &NamedChain) -> Option<Address> {
    DEPLOYMENTS.get(chain).map(|d| d.implementation)
}
