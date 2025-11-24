use crate::request::fee_estimation::price::{gas, token};
use crate::request::fee_estimation::token::{Data, FeeCompatibleERC20Token, NativeToken};
use crate::request::fee_estimation::FeeEstimationResult;
use crate::request::parameters::Parameters;
use crate::AnomaPayConfig;
use alloy::providers::DynProvider;
use std::ops::{Add, Mul};

/// The transaction base fee.
/// Based on the empty transaction execution cost.
const BASE_FEE: u128 = 30_000;

/// The fee per resource.
const RESOURCE_FEE: u128 = 500_000;

pub async fn estimate_fee_unit_quantity(
    config: &AnomaPayConfig,
    provider: &DynProvider,
    fee_token: FeeCompatibleERC20Token,
    transaction: Parameters,
) -> FeeEstimationResult<u128> {
    let resource_count = transaction.consumed_resources.len() + transaction.created_resources.len();

    estimate_fee_unit_quantity_by_resource_count(config, provider, fee_token, resource_count).await
}

pub(crate) async fn estimate_fee_unit_quantity_by_resource_count(
    config: &AnomaPayConfig,
    provider: &DynProvider,
    fee_token: FeeCompatibleERC20Token,
    resource_count: usize,
) -> FeeEstimationResult<u128> {
    let gas_units = BASE_FEE.add(RESOURCE_FEE.mul(resource_count as u128));
    let gas_price = gas::gas_price(provider).await?;

    let gas_fees_in_wei = gas_units.mul(gas_price);

    let gas_fees_in_ether: f64 =
        gas_fees_in_wei as f64 / 10f64.powi(NativeToken::ETH.decimals() as i32);

    let tokens_per_ether = token::get_token_price_in_ether(config, fee_token).await?;

    let gas_fees_in_token_units =
        gas_fees_in_ether * tokens_per_ether * 10f64.powi(NativeToken::ETH.decimals() as i32);

    let gas_fees_in_token_units = gas_fees_in_token_units.ceil() as u128;

    Ok(gas_fees_in_token_units)
}
