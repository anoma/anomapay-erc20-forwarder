use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    DecodingError, EncodingError, TransactionCreationError,
    TransactionSubmitError,
};
use crate::evm::evm_calls::pa_submit_transaction;
use crate::requests::resource::JsonResource;
use crate::requests::Expand;
use crate::transactions::split::SplitParameters;
use crate::AnomaPayConfig;
use arm::authorization::{AuthorizationSignature, AuthorizationVerifyingKey};
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::transaction::Transaction;
use k256::AffinePoint;
use serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;

#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq, Clone)]
pub struct SplitRequest {
    pub to_split_resource: JsonResource,
    pub created_resource: JsonResource,
    pub remainder_resource: JsonResource, // A second resource with the remaining quantity will be created for the owner.
    pub padding_resource: JsonResource, // A second resource with the remaining quantity will be created for the owner.
    #[serde_as(as = "Base64")]
    pub sender_nf_key: Vec<u8>,
    pub sender_verifying_key: AffinePoint,
    #[serde_as(as = "Base64")]
    pub auth_signature: Vec<u8>,
    pub owner_discovery_pk: AffinePoint,
    pub owner_encryption_pk: AffinePoint,
    pub receiver_discovery_pk: AffinePoint,
    pub receiver_encryption_pk: AffinePoint,
}

impl SplitRequest {
    pub fn to_params(&self, _config: &AnomaPayConfig) -> Result<SplitParameters, TransactionError> {
        let to_split_resource: Resource =
            Expand::expand(self.to_split_resource.clone()).map_err(|_| DecodingError)?;
        let created_resource: Resource =
            Expand::expand(self.created_resource.clone()).map_err(|_| DecodingError)?;
        let padding_resource: Resource =
            Expand::expand(self.padding_resource.clone()).map_err(|_| DecodingError)?;
        let remainder_resource: Resource =
            Expand::expand(self.remainder_resource.clone()).map_err(|_| DecodingError)?;
        let receiver_discovery_pk = self.receiver_discovery_pk;
        let receiver_encryption_pk = self.receiver_encryption_pk;
        let sender_nullifier_key: NullifierKey =
            NullifierKey::from_bytes(self.sender_nf_key.as_slice());
        let sender_auth_verifying_key: AuthorizationVerifyingKey =
            AuthorizationVerifyingKey::from_affine(self.sender_verifying_key);

        let auth_signature: AuthorizationSignature =
            AuthorizationSignature::from_bytes(self.auth_signature.as_slice())
                .map_err(|_| EncodingError)?;

        let owner_discovery_pk = self.owner_discovery_pk;
        let owner_encryption_pk = self.owner_encryption_pk;

        Ok(SplitParameters {
            to_split_resource,
            created_resource,
            remainder_resource,
            padding_resource,
            sender_nullifier_key,
            sender_auth_verifying_key,
            auth_signature,
            receiver_discovery_pk,
            receiver_encryption_pk,
            sender_discovery_pk: owner_discovery_pk,
            sender_encryption_pk: owner_encryption_pk,
        })
    }
}

pub async fn handle_split_request(
    request: SplitRequest,
    config: &AnomaPayConfig,
) -> Result<(SplitParameters, Transaction), TransactionError> {
    let split_params = request.to_params(config)?;

    let transaction = split_params
        .generate_transaction(config)
        .await
        .map_err(|_| TransactionCreationError)?;

    // Submit the transaction.
    let _submit_result = pa_submit_transaction(transaction.clone())
        .await
        .map_err(|_| TransactionSubmitError)?;

    Ok((split_params, transaction))
}
