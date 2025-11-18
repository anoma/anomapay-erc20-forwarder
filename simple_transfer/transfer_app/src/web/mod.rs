use crate::ethereum::EthError;
use crate::request;
use crate::request::ProvingError;
use request::witness_data::token_transfer;
use request::witness_data::trivial;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use utoipa::ToSchema;

mod handlers;
pub mod webserver;

pub type ReqResult<T> = Result<T, RequestError>;

#[derive(Error, Debug)]
pub enum RequestError {
    #[error("Failed to generate a transaction for the given parameters: {0}")]
    TransactionGeneration(ProvingError),
    #[error("Failed to submit transaction to Ethereum: {0}")]
    Submit(EthError),
}

/// An enum type for all possible Created Resource witness to satisfy the OpenAPI schema generator.
#[derive(ToSchema, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum CreatedWitnessDataSchema {
    #[schema(value_type = trivial::CreatedEphemeral)]
    TrivialCreatedEphemeral(trivial::CreatedEphemeral),

    #[schema(value_type = token_transfer::CreatedEphemeral)]
    TokenTransferCreatedEphemeral(token_transfer::CreatedEphemeral),

    #[schema(value_type = token_transfer::CreatedPersistent)]
    TokenTransferCreatedPersistent(token_transfer::CreatedPersistent),
}

/// An enum type for all possible Consumed Resource witness to satisfy the OpenAPI schema generator.
#[derive(ToSchema, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ConsumedWitnessDataSchema {
    #[schema(value_type = trivial::CreatedEphemeral)]
    TrivialCreatedEphemeral(trivial::ConsumedEphemeral),

    #[schema(value_type = token_transfer::ConsumedEphemeral)]
    TokenTransferCreatedEphemeral(token_transfer::ConsumedEphemeral),

    #[schema(value_type = token_transfer::ConsumedPersistent)]
    TokenTransferCreatedPersistent(token_transfer::ConsumedPersistent),
}
