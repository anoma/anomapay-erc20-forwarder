//! The witness data holds all the data that is required to generate a
//! compliance proof or a logic proof for a resource. A resource can be either a
//! consumed resource, or a created resource. For each of these types there can
//! be ephemeral and persistent resources. And for each of those there are
//! token_transfer resources and trivial resources.
//!
//! Trivial resources are used as padding resources. A padding resource is used
//! to create a balanced transaction. For example, sending 1 token_transfer
//! resource to 2 people creates a transaction that consumes 1 resource, but
//! creates 2. In this case a created padding resource has to be inserted to
//! make the transaction balanced.
//!
//! The witness data structs for token transfer resources are in the
//! token_transfer file, and witness data structs for trivial resources are in
//! trivial.

pub mod token_transfer;
pub mod trivial;

use crate::request::proving::ProvingError::LogicProofGenerationError;
use crate::request::proving::ProvingResult;
use crate::request::proving::resources::ConsumedWitnessDataEnum;
use crate::request::proving::resources::CreatedWitnessDataEnum;
use crate::{AnomaPayConfig, time_it};
use arm::Digest;
use arm::logic_proof::{LogicProver, LogicVerifier};
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::proving_system::ProofType;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;
use async_trait::async_trait;
use enum_dispatch::enum_dispatch;
use log::info;
use transfer_library::TransferLogic;
use typetag;

/// This enum can hold all the possible witness types we expect to deal with within the application.
/// The first type if the witness for trivial resources, the second for token transfer resources.
///
/// These types are boxed due to their size differences.
#[derive(Clone)]
pub enum WitnessTypes {
    Trivial(Box<TrivialLogicWitness>),
    Token(Box<TransferLogic>),
}

impl WitnessTypes {
    pub fn prove(&self) -> ProvingResult<LogicVerifier> {
        match self {
            WitnessTypes::Trivial(witness) => {
                time_it!(
                    "logic proof",
                    witness.prove(ProofType::Groth16).map_err(|err| {
                        println!("error: {:?}", err);
                        LogicProofGenerationError(err.to_string())
                    })
                )
            }
            WitnessTypes::Token(witness) => {
                time_it!(
                    "logic proof",
                    witness.prove(ProofType::Groth16).map_err(|err| {
                        println!("error: {:?}", err);
                        LogicProofGenerationError(err.to_string())
                    })
                )
            }
        }
    }
}
/// The `ConsumedWitnessData` trait implements the behavior that is required for
/// all witnessdata for consumed resources.
#[async_trait]
#[typetag::serde(tag = "type")]
#[enum_dispatch]
pub trait ConsumedWitnessData: Send + Sync {
    fn logic_witness(
        &self,
        resource: Resource,
        action_tree_root: Digest,
        nullifier_key: NullifierKey,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes>;

    async fn merkle_path(
        &self,
        config: &AnomaPayConfig,
        commitment: Digest,
    ) -> ProvingResult<MerklePath>;
}

/// The `CreatedWitnessData` trait implements the behavior that is required for
/// all witnessdata for created resources.
#[async_trait]
#[typetag::serde(tag = "type")]
#[enum_dispatch]
pub trait CreatedWitnessData: Send + Sync {
    fn logic_witness(
        &self,
        resource: Resource,
        action_tree_root: Digest,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes>;
}
