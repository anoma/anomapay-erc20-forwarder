//! Checks the deployment parameters the scripts hold against the crates this workspace pins. The getters run on a
//! throwaway chain, so the check needs no network.

use alloy::primitives::B256;
use alloy::providers::ProviderBuilder;
use anomapay_erc20_forwarder_bindings::generated::deployment_parameters::DeploymentParameters;

#[tokio::test]
async fn logic_ref_is_the_token_transfer_id_of_the_pinned_transfer_library() {
    let provider = ProviderBuilder::new()
        .connect_anvil_with_wallet_and_config(|anvil| anvil)
        .expect("anvil");
    let parameters = DeploymentParameters::deploy(&provider)
        .await
        .expect("deploy DeploymentParameters");

    let logic_ref = parameters.LOGIC_REF().call().await.expect("logic ref");

    assert_eq!(
        logic_ref,
        B256::from_slice(transfer_library::TOKEN_TRANSFER_ID.as_bytes()),
        "Parameters.LOGIC_REF is not the TOKEN_TRANSFER_ID of the transfer_library pinned in Cargo.toml"
    );
}
