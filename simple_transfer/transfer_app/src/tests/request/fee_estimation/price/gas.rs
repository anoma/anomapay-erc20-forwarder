#[cfg(test)]
extern crate dotenv;

use crate::load_config;
use crate::rpc::create_provider;
use alloy::providers::Provider;

#[tokio::test]
async fn test_gas_price_returns_the_gas_price_in_wei() {
    dotenv::dotenv().ok();

    let config = load_config().await.expect("failed to load config");
    let provider = create_provider(&config)
        .await
        .expect("failed to create provider");

    let res = provider.get_gas_price().await;
    assert!(res.is_ok());
    assert!(res.unwrap() > 0);
}
