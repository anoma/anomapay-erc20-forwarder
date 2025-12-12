mod compliance_proof;
mod logic_proof;
pub mod parameters;

pub mod resources;
pub mod witness_data;

use crate::rpc::RpcError;
use arm::Digest;
use serde::Serialize;
use thiserror::Error;

pub type ProvingResult<T> = Result<T, ProvingError>;

#[derive(Error, Debug, Serialize)]
pub enum ProvingError {
    #[error("The nullifier key was invalid for the consumed resource.")]
    InvalidNullifierKey,
    #[error("The commitment of the created resource was not found in the action tree {0}")]
    CreatedResourceNotInActionTree(Digest),
    #[error("The nullifier for the consumed resource was not found in the action tree. {0}")]
    ConsumedResourceNotInActionTree(Digest),
    #[error("The number of consumed and created resources are not equal.")]
    ConsumedAndCreatedResourceCountMismatch,
    #[error("Failed to generate the resource logic proof for a resource: {0:?}")]
    LogicProofGenerationError(String),
    #[error("Failed to generate the compliance proof {0:?}")]
    ComplianceProofGenerationError(String),
    #[error("Failed to generate the delta proof.")]
    DeltaProofGenerationError,
    #[error("Failed to verify the transaction.")]
    TransactionVerificationError,
    #[error("Failed to get the merkle path for a consumed resource")]
    MerklePathNotFound,
    #[error("The action tree root is invalid.")]
    InvalidActionTreeRoot,
    #[error("An error occurred related to the contract bindings {0:?}.")]
    ForwarderBindingsError(erc20_forwarder_bindings::contract::BindingsError),
    #[error("An error occurred related to the RPC provider {0:?}.")]
    ProviderError(RpcError),
}
