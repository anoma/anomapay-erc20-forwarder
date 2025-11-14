mod compliance_proof;
mod logic_proof;
pub mod parameters;
/// The request module contains all the logic to deal with a request to generate
/// a transaction. Typically these requests come in via the REST api.
pub mod resources;
mod witness_data;

use thiserror::Error;

pub type ProvingResult<T> = Result<T, ProvingError>;

// TODO What's the difference?
pub type ProofResult<T> = Result<T, ProveErr>;

#[derive(Error, Debug, Clone)]
pub enum ProvingError {
    #[error("The sender's nullifier key given for burn was invalid.")]
    InvalidSenderNullifierKey,
    #[error("The commitment of the created resource was not found in the action tree.")]
    CreatedResourceNotInActionTree,
    #[error("The nullifier for the consumed resource was not found in the action tree.")]
    ConsumedResourceNotInActionTree,
    #[error("The number of consumed and created resources are not equal.")]
    #[allow(dead_code)]
    ConsumedAndCreatedResourceCountMismatch,
    #[error("Failed to generate the resource logic proof for a resource.")]
    #[allow(dead_code)]
    LogicProofGenerationError,
    #[error("Failed to generate the compliance proof.")]
    #[allow(dead_code)]
    ComplianceProofGenerationError,
    #[error("Failed to generate the delta proof.")]
    DeltaProofGenerationError,
    #[error("Failed to verify the split transaction.")]
    TransactionVerificationError,
    #[error("Async await error occurred {0}.")]
    AsyncError(String)
}

#[derive(Error, Debug)]
pub enum ProveErr {
    #[error("Error creating compliance unit")]
    ComplianceUnitCreateError(arm::error::ArmError),
    #[error("Error creating logic proof: {0}")]
    LogicProofCreateError(arm::error::ArmError),
}
