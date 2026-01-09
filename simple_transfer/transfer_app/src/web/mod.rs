use std::io::Cursor;

use crate::request::proving::witness_data::token_transfer;
use crate::request::proving::witness_data::trivial;
use crate::web;
use rocket::Request;
use rocket::http::ContentType;
use rocket::http::Status;
use rocket::response;
use rocket::response::Responder;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use utoipa::OpenApi;
use utoipa::ToSchema;

mod handlers;
pub mod serializer;
pub mod webserver;

pub type ReqResult<T> = Result<T, RequestError>;

#[derive(Error, Serialize, ToSchema, Debug)]
pub enum RequestError {
    /// An error occurred trying to generate a transaction.
    /// Chances are there is something wrong with the passed resources.
    #[error("An error occurred generating the transaction: {0:?}")]
    TransactionGeneration(String),
    #[error("Bento queue is configured")]
    QueueNotConfigured,
    /// An error occurred submitting the transaction.
    /// The transaction was generated successfully, but submitting it to the PA failed.
    #[error("An error occurred submitting the transaction: {0:?}")]
    Submit(String),
    /// An error occurred during fee estimation.
    #[error("An error occurred estimating the transaction fee: {0:?}")]
    FeeEstimation(String),
    #[error("An error occurred fetching token balances: {0:?}")]
    TokenBalances(String),
    /// An error occurred fetching token prices.
    #[error("An error occurred fetching token prices: {0:?}")]
    TokenPrices(String),
    #[error("An error occurred generating communicating with the RPC: {0:?}")]
    ProviderError(String),
    #[error("Error while connecting to: {0:?}")]
    NetworkError(String),
}

impl<'r> Responder<'r, 'static> for RequestError {
    fn respond_to(self, _req: &'r Request<'_>) -> response::Result<'static> {
        let (status, message) = match self {
            RequestError::QueueNotConfigured => {
                (Status::NotFound, "Queue not configured".to_string())
            }
            RequestError::NetworkError(msg) => (Status::ServiceUnavailable, msg),
            RequestError::TransactionGeneration(msg) => (Status::BadRequest, msg),
            RequestError::Submit(msg) => (Status::BadRequest, msg),
            RequestError::FeeEstimation(msg) => (Status::InternalServerError, msg),
            RequestError::TokenBalances(msg) => (Status::InternalServerError, msg),
            RequestError::TokenPrices(msg) => (Status::InternalServerError, msg),
            RequestError::ProviderError(msg) => (Status::InternalServerError, msg),
        };
        let json = serde_json::json!({
            "error": message,
            "status": status.code
        })
        .to_string();

        response::Response::build()
            .status(status)
            .header(ContentType::JSON)
            .sized_body(json.len(), Cursor::new(json))
            .ok()
    }
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
