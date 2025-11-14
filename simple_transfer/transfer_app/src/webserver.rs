// use crate::evm::approve::is_address_approved;
// use crate::helpers::parse_address;
// use crate::requests::approve::ApproveRequest;
// use crate::requests::burn::{handle_burn_request, BurnRequest};
// use crate::requests::mint::{handle_mint_request, MintRequest};
// use crate::requests::split::{handle_split_request, SplitRequest};
// use crate::requests::transfer::{handle_transfer_request, TransferRequest};
// use crate::requests::Expand;
// use crate::AnomaPayConfig;
// use rocket::fairing::{Fairing, Info, Kind};
// use rocket::http::{Header, Status};
// use rocket::response::status::Custom;
// use rocket::serde::json::{json, Json};
// use rocket::{catch, get, options, post, Request, Response, State};
// use serde_json::Value;
//
// /// Return the health status
// #[get("/health")]
// pub fn health() -> Custom<Json<Value>> {
//     Custom(
//         Status::Ok,
//         Json(json!({
//             "ok": "live long and prosper"
//         })),
//     )
// }
//
// /// Returns whether the given address is approved for transfers.
// #[post("/api/is-approved", data = "<payload>")]
// pub async fn is_approved(
//     payload: Json<ApproveRequest>,
//     config: &State<AnomaPayConfig>,
// ) -> Custom<Json<Value>> {
//     let config: &AnomaPayConfig = config.inner();
//
//     let approve_request = payload.into_inner();
//     let Some(address) = parse_address(approve_request.user_addr) else {
//         return Custom(
//             Status::UnprocessableEntity,
//             Json(json!({"error": "invalid user address"})),
//         );
//     };
//
//     let Some(token_addr) = parse_address(approve_request.token_addr) else {
//         return Custom(
//             Status::UnprocessableEntity,
//             Json(json!({"error": "invalid token address"})),
//         );
//     };
//
//     match is_address_approved(address, config, token_addr).await {
//         Ok(is_approved) => Custom(Status::Ok, Json(json!({"success": is_approved}))),
//         Err(_) => Custom(
//             Status::ServiceUnavailable,
//             Json(json!({"error": "failed to check approval"})),
//         ),
//     }
// }
//
// /// Handles a request from the user to mint.
// #[post("/api/mint", data = "<payload>")]
// pub async fn mint(
//     payload: Json<MintRequest>,
//     config: &State<AnomaPayConfig>,
// ) -> Custom<Json<Value>> {
//     let config: &AnomaPayConfig = config.inner();
//     let request = payload.into_inner();
//
//     // create the transaction
//     let (mint_params, _transaction, tx_hash) = match handle_mint_request(request.clone(), config)
//         .await
//     {
//         Ok(res) => res,
//         Err(err) => {
//             return Custom(
//                 Status::UnprocessableEntity,
//                 Json(
//                     json!({"error": "failed to create mint transaction", "message": format!("{}", err)}),
//                 ),
//             )
//         }
//     };
//
//     // create the response
//     Custom(
//         Status::Accepted,
//         Json(
//             json!({"transaction_hash": tx_hash, "resource": mint_params.created_resource.simplify()}),
//         ),
//     )
// }
//
// /// Handles a request from the user to mint.
// #[post("/api/transfer", data = "<payload>")]
// pub async fn transfer(
//     payload: Json<TransferRequest>,
//     config: &State<AnomaPayConfig>,
// ) -> Custom<Json<Value>> {
//     let config: &AnomaPayConfig = config.inner();
//     let request = payload.into_inner();
//
//     // create the transaction
//     let (transfer_params, _transaction, transaction_hash) = match handle_transfer_request(
//         request.clone(),
//         config,
//     )
//     .await
//     {
//         Ok(res) => res,
//         Err(err) => {
//             return Custom(
//                 Status::UnprocessableEntity,
//                 Json(
//                     json!({"error": "failed to create transfer transaction", "message": format!("{}", err)}),
//                 ),
//             )
//         }
//     };
//
//     // create the response
//     Custom(
//         Status::Accepted,
//         Json(
//             json!({"receipt": transaction_hash, "resource": transfer_params.created_resource.simplify()}),
//         ),
//     )
// }
//
// /// Handles a request from the user to burn a resource.
// #[post("/api/burn", data = "<payload>")]
// pub async fn burn(
//     payload: Json<BurnRequest>,
//     config: &State<AnomaPayConfig>,
// ) -> Custom<Json<Value>> {
//     let config: &AnomaPayConfig = config.inner();
//
//     let request = payload.into_inner();
//
//     let (_burn_parameters, _transaction, transaction_hash) = match handle_burn_request(
//         request.clone(),
//         config,
//     )
//     .await
//     {
//         Ok(res) => res,
//         Err(err) => {
//             return Custom(
//                 Status::UnprocessableEntity,
//                 Json(
//                     json!({"error": "failed to create burn transaction", "message": format!("{}", err)}),
//                 ),
//             )
//         }
//     };
//
//     // create the response
//     Custom(Status::Accepted, Json(json!({"receipt": transaction_hash})))
// }
//
// /// Handles a request from the user to split a resource.
// #[post("/api/split", data = "<payload>")]
// pub async fn split(
//     payload: Json<SplitRequest>,
//     config: &State<AnomaPayConfig>,
// ) -> Custom<Json<Value>> {
//     let config: &AnomaPayConfig = config.inner();
//     let request = payload.into_inner();
//
//     let (_split_params, _transaction, transaction_hash) = match handle_split_request(
//         request.clone(),
//         config,
//     )
//     .await
//     {
//         Ok(res) => res,
//         Err(err) => {
//             return Custom(
//                 Status::UnprocessableEntity,
//                 Json(
//                     json!({"error": "failed to create split transaction", "message": format!("{}", err)}),
//                 ),
//             )
//         }
//     };
//
//     // create the response
//     Custom(Status::Accepted, Json(json!({"receipt": transaction_hash})))
// }
//
// #[catch(422)]
// pub fn unprocessable(_req: &Request) -> Json<Value> {
//     Json(json!({"message": "error processing request. is the json valid?"}))
// }
//
// #[catch(default)]
// pub fn default_error(_req: &Request) -> Json<Value> {
//     Json(json!({"message": "error processing request"}))
// }
//
// /// Catches all OPTION requests in order to get the CORS related Fairing triggered.
// #[options("/<_..>")]
// pub fn all_options() {
//     /* Intentionally left empty */
// }
//
// pub struct Cors;
// #[rocket::async_trait]
// impl Fairing for Cors {
//     fn info(&self) -> Info {
//         Info {
//             name: "Cross-Origin-Resource-Sharing Fairing",
//             kind: Kind::Response,
//         }
//     }
//
//     async fn on_response<'r>(&self, _request: &'r Request<'_>, response: &mut Response<'r>) {
//         response.set_header(Header::new("Access-Control-Allow-Origin", "*"));
//         response.set_header(Header::new(
//             "Access-Control-Allow-Methods",
//             "POST, PATCH, PUT, DELETE, HEAD, OPTIONS, GET",
//         ));
//         response.set_header(Header::new("Access-Control-Allow-Headers", "*"));
//         response.set_header(Header::new("Access-Control-Allow-Credentials", "true"));
//     }
// }
