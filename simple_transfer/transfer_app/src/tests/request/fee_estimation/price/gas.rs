#[cfg(test)]
extern crate dotenv;

use alloy::providers::Provider;
use evm_protocol_adapter_bindings::call::protocol_adapter;

#[tokio::test]
async fn test_gas_price_returns_the_gas_price_in_wei() {
    dotenv::dotenv().ok();

    let provider = protocol_adapter().provider().clone().erased();

    let res = provider.get_gas_price().await;
    assert!(res.is_ok());
    assert!(res.unwrap() > 0);
}
