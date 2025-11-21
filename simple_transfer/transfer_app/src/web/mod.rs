use crate::request;
use request::witness_data::token_transfer;
use request::witness_data::trivial;
use rocket::Responder;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

mod handlers;
pub mod serializer;
pub mod webserver;

pub type ReqResult<T> = Result<T, RequestError>;

#[derive(Serialize, ToSchema, Responder, Debug)]
pub enum RequestError {
    /// An error occurred trying to generate a transaction.
    /// Chances are there is something wrong with the passed resources.
    #[response(status = 400)]
    TransactionGeneration(String),
    /// An error occurred submitting the transaction.
    /// The transaction was generated successfully, but submitting it to the PA failed.
    #[response(status = 400)]
    Submit(String),
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
