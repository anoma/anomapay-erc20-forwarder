//! Defines helper functions to be used in creating transactions.

use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    ComplianceUnitCreateError, LogicProofCreateError,
};
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::logic_proof::{LogicProver, LogicVerifier};
use chrono::Local;
use tokio::task::JoinHandle;

pub type TxResult<T> = Result<T, TransactionError>;

/// Create a compliance unit based on a compliance witness.
pub fn compliance_proof(compliance_witness: &ComplianceWitness) -> TxResult<ComplianceUnit> {
    ComplianceUnit::create(compliance_witness).map_err(|e| {
        println!("error: {:?}", e);
        ComplianceUnitCreateError
    })
}

/// Given a compliance witness, generates a compliance unit.
pub async fn compliance_proof_async(
    compliance_witness: &ComplianceWitness,
) -> TxResult<ComplianceUnit> {
    let compliance_witness_clone = compliance_witness.clone();
    tokio::task::spawn_blocking(move || {
        println!(
            "compliance_proof_async start {:?}",
            Local::now().format("%Y-%m-%d %H:%M:%S%.3f")
        );
        let r = compliance_proof(&compliance_witness_clone);
        println!(
            "compliance_proof_async done {:?}",
            Local::now().format("%Y-%m-%d %H:%M:%S%.3f")
        );
        r
    })
    .await
    .unwrap()
}

/// Given a logic witness, returns a logic proof.
pub fn logic_proof<T: LogicProver + Send + 'static>(transfer_logic: &T) -> TxResult<LogicVerifier> {
    transfer_logic.prove().map_err(|e| {
        println!("error: {:?}", e);
        LogicProofCreateError
    })
}

/// Given a logic witness, returns a logic proof.
pub async fn logic_proof_async<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> TxResult<LogicVerifier> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || {
        println!(
            "logic_proof_async proof start {:?}",
            Local::now().format("%Y-%m-%d %H:%M:%S%.3f")
        );
        let r = logic_proof(&transfer_logic_clone);
        println!(
            "logic_proof_async proof done {:?}",
            Local::now().format("%Y-%m-%d %H:%M:%S%.3f")
        );
        r
    })
    .await
    .unwrap()
}

/// Given a logic witness, returns a logic proof.
pub fn logic_proof_asyncc<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> JoinHandle<TxResult<LogicVerifier>> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || {
        println!(
            "logic_proof_async proof start {:?}",
            Local::now().format("%Y-%m-%d %H:%M:%S%.3f")
        );
        let r = logic_proof(&transfer_logic_clone);
        println!(
            "logic_proof_async proof done {:?}",
            Local::now().format("%Y-%m-%d %H:%M:%S%.3f")
        );
        r
    })
}

/// Given a compliance witness, generates a compliance unit.
pub fn compliance_proof_asyncc(
    compliance_witness: &ComplianceWitness,
) -> JoinHandle<TxResult<ComplianceUnit>> {
    let compliance_witness_clone = compliance_witness.clone();
    tokio::task::spawn_blocking(move || {
        println!(
            "compliance_proof_async start {:?}",
            Local::now().format("%Y-%m-%d %H:%M:%S%.3f")
        );
        let r = compliance_proof(&compliance_witness_clone);
        println!(
            "compliance_proof_async done {:?}",
            Local::now().format("%Y-%m-%d %H:%M:%S%.3f")
        );
        r
    })
}

// /// Verifies a transaction. Returns an error if verification failed.
// pub fn verify_transaction(transaction: Transaction) -> TxResult<()> {
//     transaction.verify().map_err(|_| VerificationFailure)
// }
