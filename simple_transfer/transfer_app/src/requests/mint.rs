use crate::errors::TransactionError;
use crate::errors::TransactionError::{DecodingError, InvalidKeyChain, TransactionSubmitError};

use crate::evm::evm_calls::pa_submit_transaction;
use crate::requests::resource::JsonResource;
use crate::requests::Expand;
use crate::transactions::mint::MintParameters;
use crate::AnomaPayConfig;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::transaction::Transaction;
use arm::utils::bytes_to_words;
use arm::Digest;
use k256::AffinePoint;
use serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;

/// Defines the payload sent to the API to execute a minting request on /api/minting.
#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq, Clone)]
pub struct MintRequest {
    pub consumed_resource: JsonResource,
    pub created_resource: JsonResource,
    #[serde_as(as = "Base64")]
    pub latest_cm_tree_root: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub consumed_nf_key: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub forwarder_addr: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub token_addr: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub user_addr: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub permit_nonce: Vec<u8>,
    pub permit_deadline: u64,
    #[serde_as(as = "Base64")]
    pub permit_sig: Vec<u8>,
    pub created_discovery_pk: AffinePoint,
    pub created_encryption_pk: AffinePoint,
}

impl MintRequest {
    /// Turns a MintRequest into a MintParameters struct.
    /// This ensures that all values are properly deserialized.
    pub fn to_params(&self, config: &AnomaPayConfig) -> Result<MintParameters, TransactionError> {
        let created_resource: Resource =
            Expand::expand(self.created_resource.clone()).map_err(|_| DecodingError)?;
        let consumed_resource: Resource =
            Expand::expand(self.consumed_resource.clone()).map_err(|_| DecodingError)?;
        let consumed_nullifier_key: NullifierKey =
            NullifierKey::from_bytes(self.consumed_nf_key.as_slice());

        let created_resource_commitment = created_resource.commitment();

        let consumed_resource_nullifier: Digest = consumed_resource
            .nullifier(&consumed_nullifier_key)
            .map_err(|_| InvalidKeyChain)?;

        let latest_commitment_tree_root: Digest =
            bytes_to_words(self.latest_cm_tree_root.as_slice())
                .try_into()
                .map_err(|_| DecodingError)?;

        let user_address = self.user_addr.clone();
        let permit_nonce = self.permit_nonce.clone();

        let token_address = self.token_addr.clone();
        let permit_signature = self.permit_sig.clone();
        let discovery_pk: AffinePoint = self.created_discovery_pk;
        let encryption_pk: AffinePoint = self.created_encryption_pk;
        let permit_deadline = self.permit_deadline;

        Ok(MintParameters {
            created_resource,
            consumed_resource,
            consumed_nullifier_key,
            created_resource_commitment,
            consumed_resource_nullifier,
            latest_commitment_tree_root,
            user_address,
            permit_signature,
            discovery_pk,
            encryption_pk,
            permit_deadline,
            permit_nonce,
            token_address,
            forwarder_contract_address: config.forwarder_address.to_vec(),
        })
    }
}
pub async fn handle_mint_request(
    request: MintRequest,
    config: &AnomaPayConfig,
) -> Result<(MintParameters, Transaction), TransactionError> {
    // Convert from request to parameters
    let mint_params = request.to_params(config)?;

    // Generate the transaction.
    let transaction = mint_params.generate_transaction().await?;

    // Submit the transaction.
    let _submit_result = pa_submit_transaction(transaction.clone())
        .await
        .map_err(|_| TransactionSubmitError)?;

    Ok((mint_params, transaction))
}
