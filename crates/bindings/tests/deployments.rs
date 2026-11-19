use alloy::primitives::{Address, B256};
use alloy_chains::NamedChain;
use anomapay_erc20_forwarder_bindings::addresses::{
    Environment, erc20_forwarder_address, erc20_forwarder_deployments_map, legacy_erc20_forwarder,
    legacy_erc20_forwarder_deployments_map,
};
use std::collections::HashSet;

const ENVIRONMENTS: [Environment; 2] = [Environment::Staging, Environment::Production];

#[derive(serde::Deserialize)]
struct RawProxy {
    address: String,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawEntry {
    chain_id: u64,
    proxy: RawProxy,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawLegacyEntry {
    chain_id: u64,
    forwarder: String,
    logic_ref: String,
}

#[derive(serde::Deserialize)]
struct RawDeployments {
    staging: Vec<RawEntry>,
    production: Vec<RawEntry>,
    legacy: Vec<RawLegacyEntry>,
}

fn raw_deployments() -> RawDeployments {
    serde_json::from_str(include_str!("../deployments.json"))
        .expect("deployments.json: invalid JSON")
}

fn raw_entries(environment: Environment) -> Vec<RawEntry> {
    let deployments = raw_deployments();

    match environment {
        Environment::Staging => deployments.staging,
        Environment::Production => deployments.production,
    }
}

#[test]
fn all_entries_have_valid_chain_ids() {
    for environment in ENVIRONMENTS {
        for entry in raw_entries(environment) {
            NamedChain::try_from(entry.chain_id).unwrap_or_else(|_| {
                panic!(
                    "chain ID {} of environment {environment:?} does not map to a known NamedChain variant",
                    entry.chain_id
                )
            });
        }
    }
}

#[test]
fn all_entries_have_valid_addresses() {
    for environment in ENVIRONMENTS {
        for entry in raw_entries(environment) {
            entry.proxy.address.parse::<Address>().unwrap_or_else(|_| {
                panic!(
                    "invalid proxy address '{}' for chain ID '{}' of environment {environment:?}",
                    entry.proxy.address, entry.chain_id
                )
            });
        }
    }
}

#[test]
fn no_duplicate_chain_ids_within_an_environment() {
    for environment in ENVIRONMENTS {
        let mut seen = HashSet::new();
        for entry in raw_entries(environment) {
            assert!(
                seen.insert(entry.chain_id),
                "duplicate chain ID {} in environment {environment:?}",
                entry.chain_id
            );
        }
    }
}

#[test]
fn deployments_map_has_expected_count() {
    for environment in ENVIRONMENTS {
        let map = erc20_forwarder_deployments_map(environment);
        let entries = raw_entries(environment);
        assert_eq!(
            map.len(),
            entries.len(),
            "deployments map size ({}) does not match JSON entries ({}) of environment {environment:?}",
            map.len(),
            entries.len()
        );
    }
}

#[test]
fn each_chain_is_individually_addressable() {
    for environment in ENVIRONMENTS {
        let map = erc20_forwarder_deployments_map(environment);
        for chain in map.keys() {
            assert!(
                erc20_forwarder_address(environment, chain).is_some(),
                "erc20_forwarder_address returned None for chain '{chain}' of environment {environment:?}"
            );
        }
    }
}

#[test]
fn all_legacy_entries_have_valid_chain_ids() {
    for entry in raw_deployments().legacy {
        NamedChain::try_from(entry.chain_id).unwrap_or_else(|_| {
            panic!(
                "chain ID {} of a legacy entry does not map to a known NamedChain variant",
                entry.chain_id
            )
        });
    }
}

#[test]
fn all_legacy_entries_have_valid_addresses_and_logic_refs() {
    for entry in raw_deployments().legacy {
        entry.forwarder.parse::<Address>().unwrap_or_else(|_| {
            panic!(
                "invalid legacy ERC20 forwarder address '{}' for chain ID '{}'",
                entry.forwarder, entry.chain_id
            )
        });
        entry.logic_ref.parse::<B256>().unwrap_or_else(|_| {
            panic!(
                "invalid legacy logic ref '{}' for chain ID '{}'",
                entry.logic_ref, entry.chain_id
            )
        });
    }
}

#[test]
fn no_duplicate_chain_ids_among_the_legacy_entries() {
    let mut seen = HashSet::new();
    for entry in raw_deployments().legacy {
        assert!(
            seen.insert(entry.chain_id),
            "duplicate chain ID {} among the legacy entries",
            entry.chain_id
        );
    }
}

#[test]
fn legacy_deployments_map_has_expected_count() {
    let map = legacy_erc20_forwarder_deployments_map();
    let entries = raw_deployments().legacy;
    assert_eq!(
        map.len(),
        entries.len(),
        "Legacy deployments map size ({}) does not match JSON entries ({})",
        map.len(),
        entries.len()
    );
}

#[test]
fn each_legacy_chain_is_individually_addressable() {
    for chain in legacy_erc20_forwarder_deployments_map().keys() {
        assert!(
            legacy_erc20_forwarder(chain).is_some(),
            "legacy_erc20_forwarder returned None for chain '{chain}'"
        );
    }
}
