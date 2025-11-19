//! Token transfer resources are resources that hold ERC20 tokens. These are the
//! resources that wrap these tokens and can be transferred within Anoma.

use crate::indexer::pa_merkle_path;
use crate::request::witness_data::{ConsumedWitnessData, CreatedWitnessData, WitnessTypes};
use crate::request::ProvingError::MerklePathNotFound;
use crate::request::ProvingResult;
use crate::AnomaPayConfig;
use alloy::primitives::{Address, U256};
use arm::authorization::{AuthorizationSignature, AuthorizationVerifyingKey};
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::Digest;
use async_trait::async_trait;
use k256::AffinePoint;
use rocket::serde::{Deserialize, Serialize};
use transfer_library::TransferLogic;
use utoipa::ToSchema;

/// Contains Permit2 parameters for use in consuming ephemeral erc20 resources.
#[derive(ToSchema, Deserialize, Serialize, Clone)]
pub struct Permit2Data {
    pub(crate) deadline: u64,
    #[schema(value_type = String, format = Binary)]
    pub(crate) nonce: Vec<u8>,
    #[schema(value_type = String, format = Binary)]
    pub(crate) signature: Vec<u8>,
}

//----------------------------------------------------------------------------
// Created Persistent Resource

/// The `CreatedPersistent` resource witness data holds all the information
/// necessary to create a persistent resource.
///
/// A persistent resource is created in, for example, transfer. The transferred
/// resource is created for the receiver of the resource.
#[derive(ToSchema, Deserialize, Serialize, Clone)]
pub struct CreatedPersistent {
    #[schema(value_type = String, format = Binary)]
    /// The discovery public key of the receiver (i.e., owner) of the resource.
    pub receiver_discovery_public_key: AffinePoint,
    #[schema(value_type = String, format = Binary)]
    /// The encryption public key of the receiver (i.e., owner) of the resource.
    pub receiver_encryption_public_key: AffinePoint,
}

#[typetag::serde]
impl CreatedWitnessData for CreatedPersistent {
    fn clone_box(&self) -> Box<dyn CreatedWitnessData> {
        Box::new(self.clone())
    }

    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        _config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TransferLogic::create_persistent_resource_logic(
            resource,
            resource_path,
            &self.receiver_discovery_public_key,
            self.receiver_encryption_public_key,
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
#[derive(ToSchema, Deserialize, Serialize, Clone)]
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
    fn clone_box(&self) -> Box<dyn CreatedWitnessData> {
        Box::new(self.clone())
    }

    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TransferLogic::burn_resource_logic(
            resource,
            resource_path,
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
#[derive(ToSchema, Deserialize, Serialize, Clone)]
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
    fn clone_box(&self) -> Box<dyn ConsumedWitnessData> {
        Box::new(self.clone())
    }

    #[allow(dead_code)]
    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        nullifier_key: NullifierKey,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TransferLogic::mint_resource_logic_with_permit(
            resource,
            resource_path,
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
#[derive(ToSchema, Deserialize, Serialize, Clone)]
pub struct ConsumedPersistent {
    #[schema(value_type = String, format = Binary)]
    /// TODO! Do we have to pass this via the web or not? Check with Yulia/Xuyang/Michael
    pub(crate) sender_authorization_verifying_key: AuthorizationVerifyingKey,
    #[schema(value_type = String, format = Binary)]
    /// The signature of the sender authorizing the consumption of the resource. This signature is over the entire action tree.
    pub(crate) sender_authorization_signature: AuthorizationSignature,
}

#[async_trait]
#[typetag::serde]
impl ConsumedWitnessData for ConsumedPersistent {
    fn clone_box(&self) -> Box<dyn ConsumedWitnessData> {
        Box::new(self.clone())
    }

    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        nullifier_key: NullifierKey,
        _config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TransferLogic::consume_persistent_resource_logic(
            resource,
            resource_path,
            nullifier_key,
            self.sender_authorization_verifying_key,
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
