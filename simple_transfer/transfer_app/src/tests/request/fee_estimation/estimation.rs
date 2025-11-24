#![cfg(test)]
//! Test the behavior of minting a resource.

use crate::load_config;
use crate::tests::fixtures::user_with_private_key;
use crate::tests::request::mint::example_mint_parameters;
use crate::web::webserver::estimate_fee;
use rocket::State;

#[ignore]
#[tokio::test]
async fn test_estimate_fee() {
    dotenv::dotenv().ok();

    let config = load_config().expect("failed to load config in test");
    let user = user_with_private_key(&config);
    let parameters = example_mint_parameters(user, &config, 10).await;

    assert!(estimate_fee(parameters.into(), State::from(&config))
        .await
        .is_ok());
}
