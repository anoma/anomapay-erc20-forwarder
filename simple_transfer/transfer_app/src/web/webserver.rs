use crate::request::fee_estimation::estimation::{
    estimate_fee_unit_quantity, FeeEstimationPayload,
};

use crate::request::parameters::Parameters;
use crate::rpc::create_provider;
use crate::web::handlers::handle_parameters;
use crate::web::RequestError;
use crate::AnomaPayConfig;
use rocket::fairing::{Fairing, Info, Kind};
use rocket::http::{Header, Status};
use rocket::response::status::Custom;
use rocket::serde::json::{json, Json};
use rocket::{catch, get, options, post, Request, Response, State};
use serde_json::Value;
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(paths(health, send_transaction))]
pub struct AnomaPayApi;

/// Return the health status
#[get("/health")]
#[utoipa::path(
    get,
    path = "health",
    responses(
            (status = 200, description = "Service is healthy", body = inline(Object),
            example = json!({
                "ok": "live long and prosper",
                "version": "1.0.0"
            }))),
)]
pub fn health() -> Custom<Json<Value>> {
    Custom(
        Status::Ok,
        Json(json!({
            "ok": "live long and prosper",
            "version": env!("CARGO_PKG_VERSION")
        })),
    )
}

/// Proves and executes an AnomaPay transaction and returns the Ethereum transaction hash.
#[post("/send_transaction", data = "<payload>")]
#[utoipa::path(
    post,
    path = "send_transaction",
    request_body = Parameters,
    responses(
            (status = 200, description = "Submit a transaction proving and execution request to the backend.", body = inline(Object),
            example = json!({
                "transaction_hash": "0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF",
            })),
            (status = 400, description = "Error occurred submitting transaction", body = RequestError, example = json!(RequestError::TransactionGeneration(String::from("failed to generate tx")))),
    )
)]

pub async fn send_transaction(
    payload: Json<Parameters>,
    config: &State<AnomaPayConfig>,
) -> Result<Custom<Json<Value>>, RequestError> {
    let config: &AnomaPayConfig = config.inner();
    let parameters = payload.into_inner();

    let tx_hash = handle_parameters(parameters, config)
        .await
        .map_err(|_| RequestError::TransactionGeneration("kapot".to_string()))?;

    Ok(Custom(
        Status::Accepted,
        Json(json!({"transaction_hash": tx_hash})),
    ))
}

/// Estimates a fee for a transaction request.
#[post("/estimate_fee", data = "<payload>")]
#[utoipa::path(
    post,
    path = "/estimate_fee",
    request_body = FeeEstimationPayload,
    responses(
            (status = 200, description = "Submit a fee estimation request to the backend.", body = FeeEstimationPayload),
            (status = 400, description = "Fee estimation failed.", body = RequestError, example = json!(RequestError::FeeEstimation(String::from("failed to estimate fee")))),
    )
)]

pub async fn estimate_fee(
    payload: Json<FeeEstimationPayload>,
    config: &State<AnomaPayConfig>,
) -> Result<Custom<Json<Value>>, RequestError> {
    let provider = create_provider(config)
        .await
        .map_err(|err| RequestError::ProviderError(err.to_string()))?;

    let fee =
        estimate_fee_unit_quantity(config, &provider, &payload.fee_token, &payload.transaction)
            .await
            .map_err(|err| RequestError::FeeEstimation(err.to_string()))?;

    Ok(Custom(Status::Accepted, Json(json!({"fee": fee}))))
}

#[catch(422)]
pub fn unprocessable(_req: &Request) -> Json<Value> {
    Json(json!({"message": "error processing request. is the json valid?"}))
}

#[catch(default)]
pub fn default_error(_req: &Request) -> Json<Value> {
    Json(json!({"message": "error processing request"}))
}

/// Catches all OPTION requests in order to get the CORS related Fairing triggered.
#[options("/<_..>")]
pub fn all_options() {
    /* Intentionally left empty */
}

pub struct Cors;
#[rocket::async_trait]
impl Fairing for Cors {
    fn info(&self) -> Info {
        Info {
            name: "Cross-Origin-Resource-Sharing Fairing",
            kind: Kind::Response,
        }
    }

    async fn on_response<'r>(&self, _request: &'r Request<'_>, response: &mut Response<'r>) {
        response.set_header(Header::new("Access-Control-Allow-Origin", "*"));
        response.set_header(Header::new(
            "Access-Control-Allow-Methods",
            "POST, PATCH, PUT, DELETE, HEAD, OPTIONS, GET",
        ));
        response.set_header(Header::new("Access-Control-Allow-Headers", "*"));
        response.set_header(Header::new("Access-Control-Allow-Credentials", "true"));
    }
}
