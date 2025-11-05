use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    DecodingError, EncodingError, TransactionCreationError, TransactionSubmitError,
};
use crate::evm::evm_calls::pa_submit_transaction;
use crate::requests::resource::JsonResource;
use crate::requests::Expand;
use crate::transactions::burn::BurnParameters;
use crate::AnomaPayConfig;
use alloy::primitives::Address;
use arm::authorization::{AuthorizationSignature, AuthorizationVerifyingKey};
use arm::nullifier_key::NullifierKey;
use arm::transaction::Transaction;
use k256::AffinePoint;
use rocket::serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;

/// Defines the payload sent to the API to execute a burn request on /api/burn.
#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq, Clone)]
pub struct BurnRequest {
    pub burned_resource: JsonResource,
    pub created_resource: JsonResource,
    #[serde_as(as = "Base64")]
    pub burner_nf_key: Vec<u8>,
    pub burner_verifying_key: AffinePoint,
    #[serde_as(as = "Base64")]
    pub burner_address: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub auth_signature: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub token_addr: Vec<u8>,
}

impl BurnRequest {
    pub fn to_params(&self) -> Result<BurnParameters, TransactionError> {
        let burned_resource =
            Expand::expand(self.burned_resource.clone()).map_err(|_| DecodingError)?;
        let created_resource =
            Expand::expand(self.created_resource.clone()).map_err(|_| DecodingError)?;
        let burner_nullifier_key = NullifierKey::from_bytes(self.burner_nf_key.as_slice());
        let burner_auth_verifying_key =
            AuthorizationVerifyingKey::from_affine(self.burner_verifying_key);
        let burner_address = Address::from_slice(&self.burner_address);
        let auth_signature = AuthorizationSignature::from_bytes(self.auth_signature.as_slice())
            .map_err(|_| EncodingError)?;
        let token_address = Address::from_slice(&self.token_addr);

        Ok(BurnParameters {
            burned_resource,
            created_resource,
            burner_nullifier_key,
            burner_auth_verifying_key,
            burner_address,
            auth_signature,
            token_address,
        })
    }
}

pub async fn handle_burn_request(
    request: BurnRequest,
    config: &AnomaPayConfig,
) -> Result<(BurnParameters, Transaction), TransactionError> {
    let burn_params = request.to_params()?;

    let transaction = burn_params
        .generate_transaction(config)
        .await
        .map_err(|_| TransactionCreationError)?;

    // Submit the transaction.
    let _submit_result = pa_submit_transaction(transaction.clone())
        .await
        .map_err(|_| TransactionSubmitError)?;

    Ok((burn_params, transaction))
}
