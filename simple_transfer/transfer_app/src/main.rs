//! Backend application for the Anomapay application.
mod indexer;
mod request;
mod rpc;
mod tests;
mod user;
mod web;

use crate::web::webserver::{
    all_options, default_error, health, send_transaction, unprocessable, Cors,
};
use alloy::primitives::Address;
use alloy::signers::local::PrivateKeySigner;
use rocket::form::validate::Contains;
use rocket::{catchers, launch, routes};
use std::error::Error;
use std::{env, fs};
use utoipa::OpenApi;
use utoipa_swagger_ui::SwaggerUi;
/// The `AnomaPayConfig` struct holds all necessary secret information about the Anomapay backend.
/// It contains the private key for submitting transactions, the address for the indexer, etc.
pub struct AnomaPayConfig {
    /// address of the anoma forwarder contract
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
}

/// Reads the environment for required values and sets them into the config.
#[allow(dead_code)]
fn load_config() -> Result<AnomaPayConfig, Box<dyn Error>> {
    let forwarder_address =
        env::var("FORWARDER_ADDRESS").map_err(|_| "FORWARDER_ADDRESS not set")?;
    let forwarder_address = Address::parse_checksummed(forwarder_address, None)
        .map_err(|_| "FORWARDER_ADDRESS invalid")?;

    let ethereum_rpc = env::var("ETHEREUM_RPC").map_err(|_| "ETHEREUM_RPC not set")?;
    let indexer_address = env::var("INDEXER_ADDRESS").map_err(|_| "INDEXER_ADDRESS not set")?;

    let hot_wallet_private_key: String =
        env::var("HOT_WALLET_PRIVATE_KEY").expect("HOT_WALLET_PRIVATE_KEY not found");
    let hot_wallet_private_key: PrivateKeySigner = hot_wallet_private_key
        .parse()
        .map_err(|_| "HOT_WALLET_PRIVATE_KEY invalid")?;

    let hot_wallet_address: String =
        env::var("HOT_WALLET_USER_ADDRESS").map_err(|_| "HOT_WALLET_USER_ADDRESS not set")?;
    let hot_wallet_address: Address = hot_wallet_address.parse()?;

    Ok(AnomaPayConfig {
        forwarder_address,
        ethereum_rpc,
        indexer_address,
        hot_wallet_private_key,
        hot_wallet_address,
    })
}

#[derive(OpenApi)]
#[openapi(
        nest(
            (path = "/", api = web::webserver::AnomaPayApi)
        ),
        tags(
            (name = "AnomaPay Api", description = "JSON API for the AnomaPay backend")
        ),
    )]
struct ApiDoc;

/// Generate the OpenAPI spec into a String.
fn gen_api_spec() -> String {
    ApiDoc::openapi().to_pretty_json().unwrap()
}

#[launch]
async fn rocket() -> _ {
    // Check for command-line arguments
    let args: Vec<String> = std::env::args().collect();

    if args.contains(&"--api-spec".to_string()) {
        let doc = gen_api_spec();
        fs::write("openapi.json", doc).expect("failed to write spec to file");
        std::process::exit(0);
    }

    // load the config
    let config: AnomaPayConfig = load_config().unwrap_or_else(|e| {
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
        .mount("/", routes![health, send_transaction, all_options])
        .register("/", catchers![default_error, unprocessable])
}
