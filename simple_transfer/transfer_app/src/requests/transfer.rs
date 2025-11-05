use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    DecodingError, EncodingError, TransactionCreationError, TransactionSubmitError,
};
use crate::evm::evm_calls::pa_submit_transaction;
use crate::requests::resource::JsonResource;
use crate::requests::Expand;
use crate::transactions::transfer::TransferParameters;
use crate::AnomaPayConfig;
use arm::authorization::{AuthorizationSignature, AuthorizationVerifyingKey};
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::transaction::Transaction;
use k256::AffinePoint;
use serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;

/// Struct to hold the fields for a transfer request to the api.
#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq, Clone)]
pub struct TransferRequest {
    pub transferred_resource: JsonResource,
    pub created_resource: JsonResource,
    #[serde_as(as = "Base64")]
    pub sender_nf_key: Vec<u8>,
    pub sender_verifying_key: AffinePoint,
    #[serde_as(as = "Base64")]
    pub auth_signature: Vec<u8>,
    pub receiver_discovery_pk: AffinePoint,
    pub receiver_encryption_pk: AffinePoint,
}

impl TransferRequest {
    /// Turns a TransferRequest into a TransferParameters struct.
    /// This ensures that all values are properly deserialized.
    pub fn to_params(
        &self,
        _config: &AnomaPayConfig,
    ) -> Result<TransferParameters, TransactionError> {
        // convert some bytes into their proper data structure from the request.
        let transferred_resource: Resource =
            Expand::expand(self.transferred_resource.clone()).map_err(|_| DecodingError)?;
        let created_resource: Resource =
            Expand::expand(self.created_resource.clone()).map_err(|_| DecodingError)?;

        let sender_nullifier_key: NullifierKey =
            NullifierKey::from_bytes(self.sender_nf_key.as_slice());
        let sender_auth_verifying_key: AuthorizationVerifyingKey =
            AuthorizationVerifyingKey::from_affine(self.sender_verifying_key);
        let auth_signature: AuthorizationSignature =
            AuthorizationSignature::from_bytes(self.auth_signature.as_slice())
                .map_err(|_| EncodingError)?;

        let receiver_discovery_pk = self.receiver_discovery_pk;
        let receiver_encryption_pk = self.receiver_encryption_pk;

        Ok(TransferParameters {
            transferred_resource,
            created_resource,
            sender_nullifier_key,
            sender_auth_verifying_key,
            auth_signature,
            receiver_discovery_pk,
            receiver_encryption_pk,
        })
    }
}

pub async fn handle_transfer_request(
    request: TransferRequest,
    config: &AnomaPayConfig,
) -> Result<(TransferParameters, Transaction), TransactionError> {
    let transfer_params = request.to_params(config)?;
    let transaction = transfer_params
        .generate_transaction(config)
        .await
        .map_err(|_| TransactionCreationError)?;

    // Submit the transaction.
    let _submit_result = pa_submit_transaction(transaction.clone())
        .await
        .map_err(|_| TransactionSubmitError)?;

    Ok((transfer_params, transaction))
}
