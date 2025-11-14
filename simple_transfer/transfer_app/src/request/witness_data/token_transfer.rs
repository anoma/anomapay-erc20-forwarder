use crate::request::witness_data::{ConsumedWitnessData, CreatedWitnessData};
use crate::request::ProvingResult;
use crate::AnomaPayConfig;
use alloy::primitives::{Address, U256};
use arm::authorization::{AuthorizationSignature, AuthorizationVerifyingKey};
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use k256::AffinePoint;
use transfer_library::TransferLogic;

/// Contains Permit2 parameters for use in consuming ephemeral erc20 resources.
#[derive(Clone)]
#[allow(dead_code)]
pub struct Permit2Data {
    pub(crate) deadline: u64,
    pub(crate) nonce: Vec<u8>,
    pub(crate) signature: Vec<u8>,
}

//----------------------------------------------------------------------------
// Consumed Persistent Resource

/// The `ConsumedPersistent` resource witness data holds all the information
/// necessary to consume a persistent resource.
///
/// A persistent resource is consumed in, for example, transfer. The transferred
/// resource is consumed from the sender.
#[derive(Clone)]
#[allow(dead_code)]
pub struct ConsumedPersistent {
    /// TODO! Do we have to pass this via the api or not? Check with Yulia/Xuyang/Michael
    sender_authorization_verifying_key: AuthorizationVerifyingKey,
    /// The signature of the sender authorizing the consumption of the resource. This signature is over the entire action tree.
    sender_authorization_signature: AuthorizationSignature,
}

impl ConsumedWitnessData for ConsumedPersistent {
    type WitnessType = TransferLogic;

    fn clone_box(&self) -> Box<dyn ConsumedWitnessData<WitnessType = Self::WitnessType>> {
        Box::new(self.clone())
    }

    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        nullifier_key: NullifierKey,
        _config: &AnomaPayConfig,
    ) -> ProvingResult<Self::WitnessType> {
        Ok(TransferLogic::consume_persistent_resource_logic(
            resource,
            resource_path,
            nullifier_key,
            self.sender_authorization_verifying_key,
            self.sender_authorization_signature,
        ))
    }
}

//----------------------------------------------------------------------------
// Created Persistent Resource

/// The `CreatedPersistent` resource witness data holds all the information
/// necessary to create a persistent resource.
///
/// A persistent resource is created in, for example, transfer. The transferred
/// resource is created for the receiver of the resource.
#[derive(Clone)]
#[allow(dead_code)]
pub struct CreatedPersistent {
    /// The discovery public key of the receiver (i.e., owner) of the resource.
    pub receiver_discovery_public_key: AffinePoint,
    /// The encryption public key of the receiver (i.e., owner) of the resource.
    pub receiver_encryption_public_key: AffinePoint,
}

impl CreatedWitnessData for CreatedPersistent {
    type WitnessType = TransferLogic;

    fn clone_box(&self) -> Box<dyn CreatedWitnessData<WitnessType = Self::WitnessType>> {
        Box::new(self.clone())
    }

    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        _config: &AnomaPayConfig,
    ) -> ProvingResult<Self::WitnessType> {
        Ok(TransferLogic::create_persistent_resource_logic(
            resource,
            resource_path,
            &self.receiver_discovery_public_key,
            self.receiver_encryption_public_key,
        ))
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
#[derive(Clone)]
#[allow(dead_code)]
pub struct ConsumedEphemeral {
    /// The Ethereum wallet address of the sender of the payment.
    pub sender_wallet_address: Address,
    /// The address of the ERC20 token to be deposited by wrap into an ERC20-R resource.
    pub token_contract_address: Address,
    /// The data required to create the permit2 signature.
    pub permit2_data: Permit2Data,
}

impl ConsumedWitnessData for ConsumedEphemeral {
    type WitnessType = TransferLogic;

    fn clone_box(&self) -> Box<dyn ConsumedWitnessData<WitnessType = Self::WitnessType>> {
        Box::new(self.clone())
    }

    #[allow(dead_code)]
    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        nullifier_key: NullifierKey,
        config: &AnomaPayConfig,
    ) -> ProvingResult<Self::WitnessType> {
        Ok(TransferLogic::mint_resource_logic_with_permit(
            resource,
            resource_path,
            nullifier_key,
            config.forwarder_address.to_vec(),
            self.token_contract_address.to_vec(),
            self.sender_wallet_address.to_vec(),
            self.permit2_data.nonce.clone(),
            U256::from(self.permit2_data.deadline).to_be_bytes_vec(),
            self.permit2_data.signature.clone(),
        ))
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
#[derive(Clone)]
#[allow(dead_code)]
pub struct CreatedEphemeral {
    /// The address of the ERC20 token to be withdrawn by unwrapping the ERC20-R resource.
    token_contract_address: Address,
    /// The Ethereum wallet address of the receiver of the payment.
    receiver_wallet_address: Address,
}

impl CreatedWitnessData for CreatedEphemeral {
    type WitnessType = TransferLogic;

    fn clone_box(&self) -> Box<dyn CreatedWitnessData<WitnessType = Self::WitnessType>> {
        Box::new(self.clone())
    }

    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        config: &AnomaPayConfig,
    ) -> ProvingResult<Self::WitnessType> {
        Ok(TransferLogic::burn_resource_logic(
            resource,
            resource_path,
            config.forwarder_address.to_vec(),
            self.token_contract_address.to_vec(),
            self.receiver_wallet_address.to_vec(),
        ))
    }
}
