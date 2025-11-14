//! Backend application for the Anomapay application.
mod indexer;
mod request;
mod rpc;
mod tests;
mod user;
mod web;

use crate::rpc::RpcError::InvalidRPCUrl;
use crate::web::webserver::{
    all_options, default_error, estimate_fee, health, send_transaction, token_balances,
    unprocessable, Cors,
};
use crate::web::ApiDoc;
use alloy::providers::{Provider, ProviderBuilder};
use alloy::signers::local::PrivateKeySigner;
use rocket::{catchers, launch, routes};
use std::env;
use std::error::Error;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

/// The `AnomaPayConfig` struct holds all necessary secret information about the Anomapay backend.
/// It contains the private key for submitting transactions, the address for the indexer, etc.
pub struct AnomaPayConfig {
    /// The chain ID of the ethereum network
    chain_id: u64,
    /// url of the ethereum rpc
    #[allow(dead_code)]
    ethereum_rpc: String,
    /// url of the anoma indexer
    #[allow(dead_code)]
    indexer_address: String,
    /// the private key of the hot wallet
    #[allow(dead_code)]
    hot_wallet_private_key: PrivateKeySigner,
    /// The Alchemy API key
    alchemy_api_key: String,
}

/// Reads the environment for required values and sets them into the config.
async fn load_config() -> Result<AnomaPayConfig, Box<dyn Error>> {
    let ethereum_rpc = env::var("ETHEREUM_RPC").map_err(|_| "ETHEREUM_RPC not set")?;
    let indexer_address = env::var("INDEXER_ADDRESS").map_err(|_| "INDEXER_ADDRESS not set")?;

    let hot_wallet_private_key: String =
        env::var("HOT_WALLET_PRIVATE_KEY").expect("HOT_WALLET_PRIVATE_KEY not found");
    let hot_wallet_private_key: PrivateKeySigner = hot_wallet_private_key
        .parse()
        .map_err(|_| "HOT_WALLET_PRIVATE_KEY invalid")?;

    let chain_id = ProviderBuilder::new()
        .wallet(hot_wallet_private_key.clone())
        .connect_http(ethereum_rpc.parse().map_err(|_e| InvalidRPCUrl)?)
        .erased()
        .get_chain_id()
        .await?;

    let alchemy_api_key: String =
        env::var("ALCHEMY_API_KEY").map_err(|_| "ALCHEMY_API_KEY not set")?;

    Ok(AnomaPayConfig {
        chain_id,
        ethereum_rpc,
        indexer_address,
        hot_wallet_private_key,
        alchemy_api_key,
    })
}

#[launch]
async fn rocket() -> _ {
    // load the config
    let config: AnomaPayConfig = load_config().await.unwrap_or_else(|e| {
        eprintln!("Error loading config: {e}");
        std::process::exit(1);
    });

    rocket::build()
        .manage(config)
        .attach(Cors)
        .mount(
            "/",
            SwaggerUi::new("/swagger-ui/<_..>").url("/api-docs/openapi.json", ApiDoc::openapi()),
        )
        .mount(
            "/",
            routes![health, send_transaction, estimate_fee, token_balances, all_options],
        )
        .register("/", catchers![default_error, unprocessable])
}
