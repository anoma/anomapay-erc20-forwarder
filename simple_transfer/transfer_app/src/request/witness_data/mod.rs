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

use crate::request::ProvingResult;
use crate::AnomaPayConfig;
use arm::logic_proof::LogicProver;
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::Digest;
use async_trait::async_trait;
/// The `ConsumedWitnessData` trait implements the behavior that is required for
/// all witnessdata for consumed resources.
#[async_trait]
pub trait ConsumedWitnessData {
    type WitnessType: LogicProver + Send + 'static;
    fn clone_box(&self) -> Box<dyn ConsumedWitnessData<WitnessType = Self::WitnessType>>;
    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        nullifier_key: NullifierKey,
        config: &AnomaPayConfig,
    ) -> ProvingResult<Self::WitnessType>;

    async fn merkle_path(
        &self,
        config: &AnomaPayConfig,
        commitment: Digest,
    ) -> ProvingResult<MerklePath>;
}

/// The `CreatedWitnessData` trait implements the behavior that is required for
/// all witnessdata for created resources.
#[async_trait]
pub trait CreatedWitnessData {
    type WitnessType: LogicProver + Send + 'static;
    fn clone_box(&self) -> Box<dyn CreatedWitnessData<WitnessType = Self::WitnessType>>;
    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        config: &AnomaPayConfig,
    ) -> ProvingResult<Self::WitnessType>;


}
