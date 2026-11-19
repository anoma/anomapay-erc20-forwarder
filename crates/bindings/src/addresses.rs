use alloy::primitives::{Address, B256};
use alloy_chains::NamedChain;
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::LazyLock;

/// The deployment environment of a recorded ERC20 forwarder proxy.
///
/// A release version of this crate describes both environments; a prerelease describes staging only, because
/// production trails on the previous release until the release candidate cycle ends.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Environment {
    /// The staging environment, owned by the deployment wallet and running what the `staging` branch promoted.
    Staging,
    /// The production environment, owned by a Safe and running the release the `main` branch promoted.
    Production,
}

/// The legacy ERC20 forwarder of a chain, and the logic ref it accepts.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LegacyForwarder {
    pub address: Address,
    pub logic_ref: B256,
}

#[derive(Deserialize)]
struct Proxy {
    address: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeploymentEntry {
    chain_id: u64,
    proxy: Proxy,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyEntry {
    chain_id: u64,
    forwarder: String,
    logic_ref: String,
}

#[derive(Deserialize)]
struct Deployments {
    staging: Vec<DeploymentEntry>,
    production: Vec<DeploymentEntry>,
    legacy: Vec<LegacyEntry>,
}

static DEPLOYMENTS: LazyLock<HashMap<Environment, HashMap<NamedChain, Address>>> =
    LazyLock::new(|| {
        let deployments: Deployments = serde_json::from_str(include_str!("../deployments.json"))
            .expect("deployments.json: invalid JSON");

        let to_map = |entries: Vec<DeploymentEntry>| {
            entries
                .into_iter()
                .filter_map(|e| {
                    let chain = NamedChain::try_from(e.chain_id).ok()?;
                    let proxy: Address = e.proxy.address.parse().ok()?;
                    Some((chain, proxy))
                })
                .collect()
        };

        HashMap::from([
            (Environment::Staging, to_map(deployments.staging)),
            (Environment::Production, to_map(deployments.production)),
        ])
    });

static LEGACY_DEPLOYMENTS: LazyLock<HashMap<NamedChain, LegacyForwarder>> = LazyLock::new(|| {
    let deployments: Deployments = serde_json::from_str(include_str!("../deployments.json"))
        .expect("deployments.json: invalid JSON");

    deployments
        .legacy
        .into_iter()
        .filter_map(|e| {
            let chain = NamedChain::try_from(e.chain_id).ok()?;
            let address: Address = e.forwarder.parse().ok()?;
            let logic_ref: B256 = e.logic_ref.parse().ok()?;
            Some((chain, LegacyForwarder { address, logic_ref }))
        })
        .collect()
});

/// Returns a map of the ERC20 forwarder proxies recorded for the environment.
pub fn erc20_forwarder_deployments_map(environment: Environment) -> HashMap<NamedChain, Address> {
    DEPLOYMENTS[&environment].clone()
}

/// Returns the ERC20 forwarder proxy recorded for the environment on the provided chain, if any.
pub fn erc20_forwarder_address(environment: Environment, chain: &NamedChain) -> Option<Address> {
    DEPLOYMENTS[&environment].get(chain).cloned()
}

/// Returns a map of the legacy ERC20 forwarders, one per chain that ran a legacy protocol adapter.
pub fn legacy_erc20_forwarder_deployments_map() -> HashMap<NamedChain, LegacyForwarder> {
    LEGACY_DEPLOYMENTS.clone()
}

/// Returns the legacy ERC20 forwarder recorded on the provided chain, if any.
pub fn legacy_erc20_forwarder(chain: &NamedChain) -> Option<LegacyForwarder> {
    LEGACY_DEPLOYMENTS.get(chain).copied()
}
