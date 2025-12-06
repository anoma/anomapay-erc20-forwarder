use alloy::primitives::Address;
use serde::Deserialize;
use strum::EnumIter;
use utoipa::ToSchema;

#[derive(Debug)]
pub struct TokenMetadata {
    #[allow(unused)]
    pub name: String,
    pub symbol: String,
    pub decimals: u8,
}

#[derive(Debug, Clone)]
pub enum Token {
    FeeCompatibleERC20(FeeCompatibleERC20Token),
    Native(NativeToken),
}

#[derive(Debug, Clone, EnumIter, Deserialize, ToSchema)]
#[allow(clippy::upper_case_acronyms)]
pub enum FeeCompatibleERC20Token {
    WETH,
    USDC,
    USDT
}

#[derive(Debug, Clone, EnumIter, Deserialize)]
#[allow(clippy::upper_case_acronyms)]
pub enum NativeToken {
    ETH,
}

pub trait Data {
    fn metadata(&self) -> TokenMetadata;

    fn symbol(&self) -> String {
        self.metadata().symbol.clone()
    }

    fn decimals(&self) -> u8 {
        self.metadata().decimals
    }
}

impl Data for Token {
    fn metadata(&self) -> TokenMetadata {
        match self {
            Token::FeeCompatibleERC20(fee_token) => match fee_token {
                FeeCompatibleERC20Token::WETH => TokenMetadata {
                    name: String::from("Wrapped Ether"),
                    symbol: String::from("WETH"),
                    decimals: 18,
                },
                FeeCompatibleERC20Token::USDC => TokenMetadata {
                    name: String::from("USD Coin"),
                    symbol: String::from("USDC"),
                    decimals: 6,
                },
                FeeCompatibleERC20Token::USDT => TokenMetadata {
                    name: String::from("Tether USD"),
                    symbol: String::from("USDT"),
                    decimals: 18,
                },
            },
            Token::Native(native_token) => match native_token {
                NativeToken::ETH => TokenMetadata {
                    name: String::from("Ether"),
                    symbol: String::from("ETH"),
                    decimals: 18,
                },
            },
        }
    }
}

impl From<FeeCompatibleERC20Token> for Token {
    fn from(fee_token: FeeCompatibleERC20Token) -> Self {
        Token::FeeCompatibleERC20(fee_token)
    }
}

impl From<NativeToken> for Token {
    fn from(native_token: NativeToken) -> Self {
        Token::Native(native_token)
    }
}

impl Data for NativeToken {
    fn metadata(&self) -> TokenMetadata {
        Token::Native(self.clone()).metadata()
    }
}

impl Data for FeeCompatibleERC20Token {
    fn metadata(&self) -> TokenMetadata {
        Token::FeeCompatibleERC20(self.clone()).metadata()
    }
}

/// Mainnet token addresses
mod addresses {
    use super::*;
    use alloy::primitives::address;

    pub const WETH_MAINNET: Address = address!("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
    pub const USDC_MAINNET: Address = address!("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
    pub const USDT_MAINNET: Address = address!("0xdAC17F958D2ee523a2206206994597C13D831ec7");
}

impl Token {
    /// Returns the mainnet contract address per token symbol
    /// For native ETH, returns WETH address since WETH represents ETH
    pub fn mainnet_address(&self) -> Address {
        match self {
            Token::FeeCompatibleERC20(fee_token) => match fee_token {
                FeeCompatibleERC20Token::WETH => addresses::WETH_MAINNET,
                FeeCompatibleERC20Token::USDC => addresses::USDC_MAINNET,
                FeeCompatibleERC20Token::USDT => addresses::USDT_MAINNET
            },
            Token::Native(native_token) => match native_token {
                NativeToken::ETH => addresses::WETH_MAINNET, // Use WETH for ETH
            },
        }
    }
}
