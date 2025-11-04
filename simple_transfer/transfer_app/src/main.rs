//! Backend application for the Anomapay application.
//!
//! The backend serves a JSON api to handle requests.
//! The following api's are available:
//!  - minting
//!  - transferring
//!  - splitting
//!  - burning

mod errors;

mod evm;
mod requests;
mod tests;
mod transactions;
mod user;
mod webserver;
mod helpers;

use crate::webserver::{
    all_options, burn, default_error, health, is_approved, mint, split, transfer, unprocessable,
    Cors,
};
use alloy::primitives::Address;
use alloy::signers::local::PrivateKeySigner;
use rocket::{catchers, launch, routes};
use std::env;
use std::error::Error;

struct AnomaPayConfig {
    // address of the anoma forwarder contract
    forwarder_address: Address,
    // url of the ethereum rpc
    ethereum_rpc: String,
    // url of the anoma indexer
    indexer_address: String,
    // the address of the hot wallet
    hot_wallet_address: Address,
    // the private key of the hot wallet
    hot_wallet_private_key: PrivateKeySigner,
}

/// Reads the environment for required values and sets them into the config.
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
#[launch]
async fn rocket() -> _ {
    // load the config
    let config: AnomaPayConfig = load_config().unwrap_or_else(|e| {
        eprintln!("Error loading config: {e}");
        std::process::exit(1);
    });

    rocket::build()
        .configure(rocket::Config::figment().merge(("port", 8001)))
        .manage(config)
        .attach(Cors)
        .mount(
            "/",
            routes![
                health,
                is_approved,
                mint,
                transfer,
                burn,
                split,
                all_options
            ],
        )
        .register("/", catchers![default_error, unprocessable])
}
