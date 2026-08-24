//! Deployment checks against the live environments. They run on the promotion gate: the
//! `VERIFY_*` flags arm them per environment, because between a version bump on `next` and the
//! environment's upgrade the source and the deployments legitimately disagree.

#[cfg(test)]
extern crate dotenvy;

use alloy::primitives::B256;
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy_chains::NamedChain;
use anoma_pa_evm_bindings::addresses::{Environment as PaEnvironment, protocol_adapter_address};
use anoma_pa_evm_bindings::helpers::alchemy_url;
use anomapay_erc20_forwarder_bindings::addresses::{Environment, erc20_forwarder_deployments_map};
use anomapay_erc20_forwarder_bindings::contract::erc20_forwarder;
use anomapay_erc20_forwarder_bindings::generated::erc20_forwarder;

const ENVIRONMENTS: [(Environment, &str); 2] = [
    (Environment::Staging, "VERIFY_STAGING_DEPLOYMENTS"),
    (Environment::Production, "VERIFY_PRODUCTION_DEPLOYMENTS"),
];

/// Maps the forwarder's environment onto the protocol adapter bindings' equivalent.
fn pa_environment(environment: Environment) -> PaEnvironment {
    match environment {
        Environment::Staging => PaEnvironment::Staging,
        Environment::Production => PaEnvironment::Production,
    }
}

/// Returns the environments whose flag arms the gate, printing a skip note for the rest.
fn armed_environments() -> Vec<Environment> {
    ENVIRONMENTS
        .into_iter()
        .filter_map(|(environment, flag)| {
            if std::env::var(flag).as_deref() == Ok("true") {
                Some(environment)
            } else {
                eprintln!("skipped: {flag} is not set");
                None
            }
        })
        .collect()
}

fn token_transfer_id() -> B256 {
    B256::from_slice(transfer_library::TOKEN_TRANSFER_ID.as_bytes())
}

#[tokio::test]
async fn deployed_forwarders_point_to_the_current_protocol_adapter_contract() {
    for environment in armed_environments() {
        for chain in erc20_forwarder_deployments_map(environment).keys() {
            let referenced_protocol_adapter = fwd_instance(chain, environment)
                .await
                .getProtocolAdapter()
                .call()
                .await
                .expect("Couldn't get protocol adapter address");

            // The forwarder settles through the protocol adapter proxy of the same environment.
            let deployed_protocol_adapter =
                protocol_adapter_address(pa_environment(environment), chain).unwrap_or_else(|| {
                    panic!("no protocol adapter recorded for network '{chain}'")
                });

            assert_eq!(
                referenced_protocol_adapter, deployed_protocol_adapter,
                "Protocol adapter address mismatch on network '{chain}' of environment {environment:?}."
            );
        }
    }
}

#[tokio::test]
async fn deployed_forwarders_reference_the_expected_logic_ref() {
    for environment in armed_environments() {
        for chain in erc20_forwarder_deployments_map(environment).keys() {
            let actual_logic_ref = fwd_instance(chain, environment)
                .await
                .getLogicRef()
                .call()
                .await
                .expect("Couldn't get logic ref");

            assert_eq!(
                actual_logic_ref,
                token_transfer_id(),
                "Logic ref mismatch on network '{chain}' of environment {environment:?}: expected {}, actual: {actual_logic_ref}.",
                token_transfer_id()
            );
        }
    }
}

#[tokio::test]
async fn versions_of_deployed_forwarders_match_the_expected_version() {
    for environment in armed_environments() {
        for chain in erc20_forwarder_deployments_map(environment).keys() {
            let existing_fwd = fwd_instance(chain, environment).await;

            // `VERSION` is a constant, so the freshly deployed implementation answers
            // it without being put behind a proxy and initialized.
            let expected_version = erc20_forwarder::ERC20Forwarder::deploy(existing_fwd.provider())
                .await
                .expect("Couldn't deploy the ERC20 forwarder implementation")
                .VERSION()
                .call()
                .await
                .expect("Couldn't get version");

            let actual_version = existing_fwd
                .VERSION()
                .call()
                .await
                .expect("Couldn't get the deployed ERC20 forwarder version");

            assert_eq!(
                actual_version, expected_version,
                "ERC20 forwarder version mismatch on network '{chain}' of environment {environment:?}."
            );
        }
    }
}

async fn fwd_instance(
    chain: &NamedChain,
    environment: Environment,
) -> erc20_forwarder::ERC20Forwarder::ERC20ForwarderInstance<DynProvider> {
    let rpc_url = alchemy_url(chain).expect("Couldn't get RPC URL for chain");

    let provider = ProviderBuilder::new()
        .connect_anvil_with_wallet_and_config(|a| a.fork(rpc_url))
        .expect("Couldn't create anvil provider");
    erc20_forwarder(&provider.erased(), environment)
        .await
        .expect("Couldn't get ERC20 forwarder instance")
}
