//! Token transfer resources are resources that hold ERC20 tokens. These are the
//! resources that wrap these tokens and can be transferred within Anoma.

use crate::indexer::pa_merkle_path;
use crate::request::witness_data::{ConsumedWitnessData, CreatedWitnessData, WitnessTypes};
use crate::request::ProvingError::MerklePathNotFound;
use crate::request::ProvingResult;
use crate::web::serializer::serialize_affine_point;
use crate::web::serializer::serialize_auth_verifying_key;
use crate::web::serializer::serialize_authorization_signature;
use crate::AnomaPayConfig;
use alloy::primitives::{Address, U256};
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::Digest;
use arm_gadgets::authorization::{AuthorizationSignature, AuthorizationVerifyingKey};
use async_trait::async_trait;
use k256::AffinePoint;
use rocket::serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;
use transfer_library::TransferLogic;
use utoipa::ToSchema;

/// Contains Permit2 parameters for use in consuming ephemeral erc20 resources.
#[serde_as]
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
pub struct Permit2Data {
    pub(crate) deadline: u64,
    #[schema(value_type = String, format = Binary)]
    #[serde_as(as = "Base64")]
    pub(crate) nonce: Vec<u8>,
    #[schema(value_type = String, format = Binary)]
    #[serde_as(as = "Base64")]
    pub(crate) signature: Vec<u8>,
}

//----------------------------------------------------------------------------
// Created Persistent Resource

/// The `CreatedPersistent` resource witness data holds all the information
/// necessary to create a persistent resource.
///
/// A persistent resource is created in, for example, transfer. The transferred
/// resource is created for the receiver of the resource.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
#[schema(as=TokenTransferCreatedPersistent)]
pub struct CreatedPersistent {
    #[schema(value_type = String, format = Binary)]
    #[serde(with = "serialize_affine_point")]
    /// The discovery public key of the receiver (i.e., owner) of the resource.
    pub receiver_discovery_public_key: AffinePoint,
    #[schema(value_type = String, format = Binary)]
    #[serde(with = "serialize_auth_verifying_key")]
    pub(crate) receiver_authorization_verifying_key: AuthorizationVerifyingKey,
    #[schema(value_type = String, format = Binary)]
    #[serde(with = "serialize_affine_point")]
    /// The encryption public key of the receiver (i.e., owner) of the resource.
    pub receiver_encryption_public_key: AffinePoint,
    /// The address of the ERC20 token that the resource wraps.
    #[schema(value_type = String, format = Binary)]
    pub(crate) token_contract_address: Address,
}

#[typetag::serde]
impl CreatedWitnessData for CreatedPersistent {
    fn logic_witness(
        &self,
        resource: Resource,
        action_tree_root: Digest,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TransferLogic::create_persistent_resource_logic(
            resource,
            action_tree_root,
            &self.receiver_discovery_public_key,
            self.receiver_authorization_verifying_key,
            self.receiver_encryption_public_key,
            config.forwarder_address.to_vec(),
            self.token_contract_address.to_vec(),
        );
        Ok(WitnessTypes::Token(Box::new(witness)))
    }
}

//----------------------------------------------------------------------------
// Created Ephemeral Resource

/// The `CreatedEphemeral` resource holds all the witness data to create an
/// ephemeral resource.
///
/// An ephemeral resource is created in, for example, burning. The user unwraps
/// an ERC20 token and the resource that held it is consumed. To balance the
/// transaction an ephemeral resource is created.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
#[schema(as=TokenTransferCreatedEphemeral)]
pub struct CreatedEphemeral {
    #[schema(value_type = String, format = Binary)]
    /// The address of the ERC20 token to be withdrawn by unwrapping the ERC20-R resource.
    pub(crate) token_contract_address: Address,
    #[schema(value_type = String, format = Binary)]
    /// The Ethereum wallet address of the receiver of the payment.
    pub(crate) receiver_wallet_address: Address,
}

#[typetag::serde]
impl CreatedWitnessData for CreatedEphemeral {
    fn logic_witness(
        &self,
        resource: Resource,
        action_tree_root: Digest,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TransferLogic::burn_resource_logic(
            resource,
            action_tree_root,
            config.forwarder_address.to_vec(),
            self.token_contract_address.to_vec(),
            self.receiver_wallet_address.to_vec(),
        );
        Ok(WitnessTypes::Token(Box::new(witness)))
    }
}

//----------------------------------------------------------------------------
// Consumed Ephemeral Resource

/// The `ConsumedEphemeral` resource holds all the witness data to consume an
/// ephemeral resource.
///
/// An ephemeral resource is consumed in, for example, minting. The user wraps
/// an ERC20 token and a new resource is created. To balance the transaction an
/// ephemeral resource is consumed.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
#[schema(as=TokenTransferConsumedEphemeral)]
pub struct ConsumedEphemeral {
    #[schema(value_type = String, format = Binary)]
    /// The Ethereum wallet address of the sender of the payment.
    pub sender_wallet_address: Address,
    #[schema(value_type = String, format = Binary)]
    /// The address of the ERC20 token to be deposited by wrap into an ERC20-R resource.
    pub token_contract_address: Address,
    /// The data required to create the permit2 signature.
    pub permit2_data: Permit2Data,
}

#[async_trait]
#[typetag::serde]
impl ConsumedWitnessData for ConsumedEphemeral {
    #[allow(dead_code)]
    fn logic_witness(
        &self,
        resource: Resource,
        action_tree_root: Digest,
        nullifier_key: NullifierKey,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TransferLogic::mint_resource_logic_with_permit(
            resource,
            action_tree_root,
            nullifier_key,
            config.forwarder_address.to_vec(),
            self.token_contract_address.to_vec(),
            self.sender_wallet_address.to_vec(),
            self.permit2_data.nonce.clone(),
            U256::from(self.permit2_data.deadline).to_be_bytes_vec(),
            self.permit2_data.signature.clone(),
        );
        Ok(WitnessTypes::Token(Box::new(witness)))
    }

    async fn merkle_path(
        &self,
        _config: &AnomaPayConfig,
        _commitment: Digest,
    ) -> ProvingResult<MerklePath> {
        Ok(MerklePath::empty())
    }
}

//----------------------------------------------------------------------------
// Consumed Persistent Resource

/// The `ConsumedPersistent` resource witness data holds all the information
/// necessary to consume a persistent resource.
///
/// A persistent resource is consumed in, for example, transfer. The transferred
/// resource is consumed from the sender.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
#[schema(as=TokenTransferConsumedPersistent)]
pub struct ConsumedPersistent {
    #[schema(value_type = String, format = Binary)]
    #[serde(with = "serialize_auth_verifying_key")]
    /// TODO! Do we have to pass this via the web or not? Check with Yulia/Xuyang/Michael
    pub(crate) sender_authorization_verifying_key: AuthorizationVerifyingKey,
    #[schema(value_type = String, format = Binary)]
    #[serde(with = "serialize_affine_point")]
    /// The encryption public key of the sender.
    pub sender_encryption_public_key: AffinePoint,
    #[schema(value_type = String, format = Binary)]
    #[serde(with = "serialize_authorization_signature")]
    /// The signature of the sender authorizing the consumption of the resource. This signature is over the entire action tree.
    pub(crate) sender_authorization_signature: AuthorizationSignature,
}

#[async_trait]
#[typetag::serde]
impl ConsumedWitnessData for ConsumedPersistent {
    fn logic_witness(
        &self,
        resource: Resource,
        action_tree_root: Digest,
        nullifier_key: NullifierKey,
        _config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TransferLogic::consume_persistent_resource_logic(
            resource,
            action_tree_root,
            nullifier_key,
            self.sender_authorization_verifying_key,
            self.sender_encryption_public_key,
            self.sender_authorization_signature,
        );
        Ok(WitnessTypes::Token(Box::new(witness)))
    }

    async fn merkle_path(
        &self,
        config: &AnomaPayConfig,
        commitment: Digest,
    ) -> ProvingResult<MerklePath> {
        pa_merkle_path(config, commitment).await.map_err(|e| {
            println!("merkle_path error : {}", e);
            MerklePathNotFound
        })
    }
}
