use crate::request::parameters::Parameters;
use crate::web::handlers::handle_parameters;
use crate::AnomaPayConfig;
use rocket::fairing::{Fairing, Info, Kind};
use rocket::http::{Header, Status};
use rocket::response::status::Custom;
use rocket::serde::json::{json, Json};
use rocket::{catch, get, options, post, Request, Response, State};
use serde_json::Value;
use utoipa::OpenApi;

#[derive(OpenApi)]
#[openapi(paths(health, transfer))]
pub struct AnomaPayApi;

/// Return the health status
#[get("/health")]
#[utoipa::path(
    get,
    path = "/health",
    responses(
            (status = 200, description = "Service is healthy"),
    )
)]
pub fn health() -> Custom<Json<Value>> {
    Custom(
        Status::Ok,
        Json(json!({
            "ok": "live long and prosper"
        })),
    )
}

/// Handles a request from the user to mint.
#[post("/web/transfer", data = "<payload>")]
#[utoipa::path(
    post,
    path = "/transfer",
    responses(
            (status = 200, description = "Submit a transfer request to the backend.", body = Parameters),
    )
)]
pub async fn transfer(
    payload: Json<Parameters>,
    config: &State<AnomaPayConfig>,
) -> Custom<Json<Value>> {
    let config: &AnomaPayConfig = config.inner();
    let parameters = payload.into_inner();

    let result = handle_parameters(parameters, config).await;
    let tx_hash = match result {
        Ok(tx_hash) => tx_hash,
        Err(err) => {
            return Custom(
                Status::UnprocessableEntity,
                Json(
                    json!({"error": "failed to create transaction", "message": format!("{}", err)}),
                ),
            )
        }
    };

    // create the response
    Custom(Status::Accepted, Json(json!({"transaction_hash": tx_hash})))
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
