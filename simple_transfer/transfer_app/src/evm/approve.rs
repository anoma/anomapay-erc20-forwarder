use alloy::sol;

use crate::evm::EvmError::{ContractCallError, InvalidEthereumRPC};
use crate::evm::{EvmResult, PERMIT2_CONTRACT};
use crate::AnomaPayConfig;
use alloy::primitives::Address;
use alloy::providers::ProviderBuilder;

// solidity interface code taken from
// https://sepolia.etherscan.io/address/0xda317c1d3e835dd5f1be459006471acaa1289068#code
sol! {
#[sol(rpc)]
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}}

/// Checks if a given user address has approval for permit2
pub async fn is_address_approved(
    token_holder: Address,
    config: &AnomaPayConfig,
    token_address: Address,
) -> EvmResult<bool> {
    // call the contract to check if the user approved
    let url = config
        .ethereum_rpc
        .parse()
        .map_err(|_| InvalidEthereumRPC)?;
    let provider = ProviderBuilder::new().connect_http(url);

    // create a contract instance
    let contract = IERC20::new(token_address, provider.clone());

    let res = contract
        .allowance(token_holder, PERMIT2_CONTRACT)
        .call()
        .await
        .map_err(ContractCallError)?;

    Ok(res != 0)
}
