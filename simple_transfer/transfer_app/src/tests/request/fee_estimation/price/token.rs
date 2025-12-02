#[cfg(test)]
extern crate dotenv;

use crate::load_config;
use crate::request::fee_estimation::price::token::get_token_prices;
use crate::request::fee_estimation::token::{FeeCompatibleERC20Token, NativeToken, Token};
use strum::IntoEnumIterator;

#[tokio::test]
async fn test_token_price_fetches_prices_for_all_supported_tokens() {
    dotenv::dotenv().ok();
    let config = load_config().await.expect("failed to load config in test");

    let tokens: Vec<Token> = vec![
        FeeCompatibleERC20Token::iter().next().unwrap().into(),
        NativeToken::iter().next().unwrap().into(),
    ];

    let res = get_token_prices(&config, tokens.clone()).await;

    assert!(res.is_ok());
    assert_eq!(res.unwrap().data.len(), tokens.len());
}
