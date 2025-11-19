//! Backend application for the Anomapay application.
mod indexer;
mod request;
mod rpc;
mod tests;
mod user;

use alloy::primitives::Address;
use alloy::signers::local::PrivateKeySigner;
use std::env;
use std::error::Error;

struct AnomaPayConfig {
    // address of the anoma forwarder contract
    forwarder_address: Address,
    // url of the ethereum rpc
    #[allow(dead_code)]
    ethereum_rpc: String,
    // url of the anoma indexer
    #[allow(dead_code)]
    indexer_address: String,
    // the address of the hot wallet
    #[allow(dead_code)]
    hot_wallet_address: Address,
    // the private key of the hot wallet
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

#[tokio::main]
async fn main() {}
// #[launch]
// async fn rocket() -> _ {
//     // load the config
//     let config: AnomaPayConfig = load_config().unwrap_or_else(|e| {
//         eprintln!("Error loading config: {e}");
//         std::process::exit(1);
//     });
//
//     rocket::build()
//         .manage(config)
//         .attach(Cors)
//         .mount(
//             "/",
//             routes![
//                 health,
//                 is_approved,
//                 mint,
//                 transfer,
//                 burn,
//                 split,
//                 all_options
//             ],
//         )
//         .register("/", catchers![default_error, unprocessable])
// }
