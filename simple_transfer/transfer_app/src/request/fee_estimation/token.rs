use strum::EnumIter;

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

#[derive(Debug, Clone, EnumIter)]
#[allow(clippy::upper_case_acronyms)]
pub enum FeeCompatibleERC20Token {
    WETH,
    USDC,
    XAN,
}

#[derive(Debug, Clone, EnumIter)]
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
                FeeCompatibleERC20Token::XAN => TokenMetadata {
                    name: String::from("Anoma"),
                    symbol: String::from("XAN"),
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
