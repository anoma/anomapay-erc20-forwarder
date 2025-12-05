use crate::request::proving::witness_data::token_transfer;
use crate::request::proving::witness_data::trivial;
use crate::web;
use rocket::Responder;
use serde::{Deserialize, Serialize};
use utoipa::OpenApi;
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
    /// An error occurred during fee estimation.
    #[response(status = 400)]
    FeeEstimation(String),
    /// An error occurred fetching token balances.
    #[response(status = 400)]
    TokenBalances(String),
    /// An error occurred fetching token prices.
    #[response(status = 400)]
    TokenPrices(String),
    #[response(status = 400)]
    ProviderError(String),
}

/// An enum type for all possible Created Resource witness to satisfy the OpenAPI schema generator.
#[allow(clippy::large_enum_variant)]
#[derive(ToSchema, Serialize, Deserialize)]
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
pub enum ConsumedWitnessDataSchema {
    #[schema(value_type = trivial::ConsumedEphemeral)]
    TrivialCreatedEphemeral(trivial::ConsumedEphemeral),

    #[schema(value_type = token_transfer::ConsumedEphemeral)]
    TokenTransferCreatedEphemeral(token_transfer::ConsumedEphemeral),

    #[schema(value_type = token_transfer::ConsumedPersistent)]
    TokenTransferCreatedPersistent(token_transfer::ConsumedPersistent),
}

/// Struct that represents the OpenAPI specification.
/// Used to render it to json and serve up via the endpoint.
#[derive(OpenApi)]
#[openapi(
        nest(
            (path = "/", api = web::webserver::AnomaPayApi)
        ),
        tags(
            (name = "AnomaPay Api", description = "JSON API for the AnomaPay backend")
        ),
    )]
pub struct ApiDoc;
