//! Backend application for the Anomapay application.
mod indexer;
mod request;
mod rpc;
mod tests;
mod user;
mod web;

use crate::rpc::RpcError::InvalidRPCUrl;
use crate::web::ApiDoc;
use crate::web::webserver::{
    Cors, all_options, default_error, estimate_fee, health, queue_stats, send_transaction,
    token_balances, token_price, unprocessable,
};
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
    /// The URL of the Ethereum RPC
    #[allow(dead_code)]
    rpc_url: String,
    /// The URL of the Anoma Galileo indexer
    #[allow(dead_code)]
    indexer_address: String,
    /// The private key of the fee payment wallet
    #[allow(dead_code)]
    fee_payment_wallet_private_key: PrivateKeySigner,
    /// The Alchemy API key
    alchemy_api_key: String,
    /// Queue base URL
    pub queue_base_url: Option<String>,
}

/// Reads the environment for required values and sets them into the config.
async fn load_config() -> Result<AnomaPayConfig, Box<dyn Error>> {
    let rpc_url = env::var("RPC_URL").map_err(|_| "RPC_URL not set")?;

    // Verify that the bonsai variables are set, if not throw an error.
    let _ = env::var("BONSAI_API_URL").map_err(|_| "BONSAI_API_URL not set")?;
    let _ = env::var("BONSAI_API_KEY").map_err(|_| "BONSAI_API_KEY not set")?;

    let indexer_address =
        env::var("GALILEO_INDEXER_ADDRESS").map_err(|_| "GALILEO_INDEXER_ADDRESS not set")?;

    let fee_payment_wallet_private_key: PrivateKeySigner =
        env::var("FEE_PAYMENT_WALLET_PRIVATE_KEY")
            .expect("FEE_PAYMENT_WALLET_PRIVATE_KEY not found")
            .parse()
            .map_err(|_| "FEE_PAYMENT_WALLET_PRIVATE_KEY invalid")?;

    let chain_id = ProviderBuilder::new()
        .wallet(fee_payment_wallet_private_key.clone())
        .connect_http(rpc_url.parse().map_err(|_e| InvalidRPCUrl)?)
        .erased()
        .get_chain_id()
        .await?;

    let alchemy_api_key = env::var("ALCHEMY_API_KEY").map_err(|_| "ALCHEMY_API_KEY not set")?;

    let queue_base_url = env::var("QUEUE_BASE_URL").ok();

    Ok(AnomaPayConfig {
        chain_id,
        rpc_url,
        indexer_address,
        fee_payment_wallet_private_key,
        alchemy_api_key,
        queue_base_url,
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
            routes![
                health,
                send_transaction,
                estimate_fee,
                token_balances,
                token_price,
                queue_stats,
                all_options
            ],
        )
        .register("/", catchers![default_error, unprocessable])
}
