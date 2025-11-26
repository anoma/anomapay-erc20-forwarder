use crate::request::fee_estimation::price::{gas, token};
use crate::request::fee_estimation::token::{Data, FeeCompatibleERC20Token, NativeToken, Token};
use crate::request::fee_estimation::FeeEstimationResult;
use crate::request::parameters::Parameters;
use crate::AnomaPayConfig;
use alloy::providers::DynProvider;
use k256::elliptic_curve::ff::derive::bitvec::macros::internal::funty::Fundamental;
use rocket::serde::Deserialize;
use std::ops::{Add, Mul};
use utoipa::ToSchema;

/// The transaction base fee.
/// Based on the empty transaction execution cost.
const BASE_FEE: u128 = 30_000;

/// The fee per resource.
const RESOURCE_FEE: u128 = 500_000;

#[derive(ToSchema, Deserialize)]
pub struct FeeEstimationPayload {
    pub fee_token: FeeCompatibleERC20Token,
    pub transaction: Parameters,
}

pub async fn estimate_fee_unit_quantity(
    config: &AnomaPayConfig,
    provider: &DynProvider,
    fee_token: &FeeCompatibleERC20Token,
    transaction: &Parameters,
) -> FeeEstimationResult<u128> {
    let resource_count = transaction.consumed_resources.len() + transaction.created_resources.len();

    estimate_fee_resource_quantity_by_resource_count(config, provider, fee_token, resource_count)
        .await
}

pub(crate) async fn estimate_fee_resource_quantity_by_resource_count(
    config: &AnomaPayConfig,
    provider: &DynProvider,
    fee_token: &FeeCompatibleERC20Token,
    resource_count: usize,
) -> FeeEstimationResult<u128> {
    let gas = BASE_FEE.add(RESOURCE_FEE.mul(resource_count as u128));
    let gas_price_in_wei = gas::gas_price(provider).await?;

    let gas_fees_in_wei = gas.mul(gas_price_in_wei);

    let gas_fees_in_ether: f64 =
        gas_fees_in_wei as f64 / 10f64.powi(NativeToken::ETH.decimals() as i32);

    let token_price_in_ether =
        token::get_token_price_in_ether(config, &Token::FeeCompatibleERC20(fee_token.clone()))
            .await?;

    let gas_fees_in_token_units: u128 =
        (gas_fees_in_ether * token_price_in_ether * 10f64.powi(NativeToken::ETH.decimals() as i32))
            .ceil()
            .as_u128();

    Ok(gas_fees_in_token_units)
}
