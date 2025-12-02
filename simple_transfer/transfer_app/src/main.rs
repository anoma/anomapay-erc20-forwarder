//! Backend application for the Anomapay application.
mod indexer;
mod request;
mod rpc;
mod tests;
mod user;
mod web;

use crate::rpc::RpcError::InvalidRPCUrl;
use crate::web::webserver::{
    all_options, default_error, estimate_fee, health, send_transaction, unprocessable, Cors,
};
use crate::web::ApiDoc;
use alloy::primitives::Address;
use alloy::providers::{Provider, ProviderBuilder};
use alloy::signers::local::PrivateKeySigner;
use erc20_forwarder_bindings::contract::erc20_forwarder;
use rocket::{catchers, launch, routes};
use std::env;
use std::error::Error;
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;

/// The `AnomaPayConfig` struct holds all necessary secret information about the Anomapay backend.
/// It contains the private key for submitting transactions, the address for the indexer, etc.
pub struct AnomaPayConfig {
    /// The address of the ERC20 forwarder contract
    forwarder_address: Address,
    /// url of the ethereum rpc
    #[allow(dead_code)]
    ethereum_rpc: String,
    /// url of the anoma indexer
    #[allow(dead_code)]
    indexer_address: String,
    /// the address of the hot wallet
    #[allow(dead_code)]
    hot_wallet_address: Address,
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

    let provider = ProviderBuilder::new()
        .wallet(hot_wallet_private_key.clone())
        .connect_http(ethereum_rpc.parse().map_err(|_e| InvalidRPCUrl)?)
        .erased();

    let forwarder_address: Address = erc20_forwarder(&provider).await?.address().clone();

    let hot_wallet_address: String =
        env::var("HOT_WALLET_USER_ADDRESS").map_err(|_| "HOT_WALLET_USER_ADDRESS not set")?;
    let hot_wallet_address: Address = hot_wallet_address.parse()?;

    let alchemy_api_key: String =
        env::var("ALCHEMY_API_KEY").map_err(|_| "ALCHEMY_API_KEY not set")?;

    Ok(AnomaPayConfig {
        forwarder_address,
        ethereum_rpc,
        indexer_address,
        hot_wallet_private_key,
        hot_wallet_address,
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
            routes![health, send_transaction, estimate_fee, all_options],
        )
        .register("/", catchers![default_error, unprocessable])
}
