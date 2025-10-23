use crate::errors::TransactionError;
use crate::errors::TransactionError::{ComplianceUnitCreateError, LogicProofCreateError};
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::logic_proof::{LogicProver, LogicVerifier};
use arm::Digest;

pub mod approve;
pub mod burn;
pub mod mint;
pub mod resource;
pub mod split;
pub mod transfer;

/// This trait converts from the simplified structs into their full equivalent.
/// For example, RequestResource to Resource.
pub trait Expand {
    type Struct;
    type Error;

    fn simplify(&self) -> Self::Struct;
    fn expand(json: Self::Struct) -> Result<Self, Self::Error>
    where
        Self: Sized;
}

fn to_array<const N: usize>(v: Vec<u8>, field: &str) -> Result<[u8; N], String> {
    v.try_into().map_err(|_| format!("{} invalid size", field))
}

fn to_digest(v: Vec<u8>, field: &str) -> Result<Digest, String> {
    v.try_into().map_err(|_| format!("{} invalid size", field))
}

/// Given a compliance witness, generates a compliance unit.
pub async fn compliance_proof(
    compliance_witness: &ComplianceWitness,
) -> Result<ComplianceUnit, TransactionError> {
    let compliance_witness_clone = compliance_witness.clone();
    tokio::task::spawn_blocking(move || {
        ComplianceUnit::create(&compliance_witness_clone).map_err(|_| ComplianceUnitCreateError)
    })
    .await
    .unwrap()
}

/// Given a logic witness, returns a logic proof.
pub async fn logic_proof<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> Result<LogicVerifier, TransactionError> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || {
        transfer_logic_clone
            .prove()
            .map_err(|_e| LogicProofCreateError)
    })
    .await
    .unwrap()
}
