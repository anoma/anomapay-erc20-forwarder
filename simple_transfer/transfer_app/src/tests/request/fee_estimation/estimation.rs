#![cfg(test)]
//! Test the behavior of minting a resource.

extern crate dotenv;
use crate::load_config;
use crate::request::fee_estimation::estimation::{
    estimate_fee_unit_quantity_by_resource_count, FeeEstimationPayload,
};
use crate::request::fee_estimation::price::token::get_token_price_in_ether;
use crate::request::fee_estimation::token::FeeCompatibleERC20Token;
use crate::tests::fixtures::user_with_private_key;
use crate::tests::request::mint::example_mint_parameters;
use crate::web::webserver::estimate_fee;
use alloy::providers::Provider;
use evm_protocol_adapter_bindings::call::protocol_adapter;
use rocket::State;

#[tokio::test]
async fn test_estimate_fee() {
    dotenv::dotenv().ok();

    let config = load_config().expect("failed to load config in test");
    let user = user_with_private_key(&config);

    let payload = FeeEstimationPayload {
        transaction: example_mint_parameters(user, &config, 10).await,
        fee_token: FeeCompatibleERC20Token::USDC,
    };

    assert!(estimate_fee(payload.into(), State::from(&config))
        .await
        .is_ok());
}

#[tokio::test]
async fn test_estimate_fee_unit_quantity() {
    dotenv::dotenv().ok();

    let config = load_config().expect("failed to load config in test");
    let provider = protocol_adapter().provider().clone().erased();

    let res = estimate_fee_unit_quantity_by_resource_count(
        &config,
        &provider,
        &FeeCompatibleERC20Token::USDC,
        2,
    )
    .await
    .expect("failed to get price");
    println!("price: {res}");
}

#[tokio::test]
async fn test_get_token_price_in_ether() {
    dotenv::dotenv().ok();

    let config = load_config().expect("failed to load config in test");

    let res = get_token_price_in_ether(&config, &FeeCompatibleERC20Token::USDC)
        .await
        .expect("failed to get price");
    println!("price: {res}");
}
