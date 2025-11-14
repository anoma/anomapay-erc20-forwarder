use crate::request::witness_data::{ConsumedWitnessData, CreatedWitnessData};
use crate::request::ProvingResult;
use crate::AnomaPayConfig;
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;

#[derive(Clone)]
#[allow(dead_code)]
/// The empty witness data for consumed ephemeral resources.
struct ConsumedEphemeral {}

#[derive(Clone)]
#[allow(dead_code)]
/// The empty witness data for consumed ephemeral resources.
struct CreatedEphemeral {}

impl ConsumedWitnessData for ConsumedEphemeral {
    type WitnessType = TrivialLogicWitness;

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
        Ok(TrivialLogicWitness::new(
            resource,
            resource_path,
            nullifier_key,
            true,
        ))
    }
}

impl CreatedWitnessData for CreatedEphemeral {
    type WitnessType = TrivialLogicWitness;

    fn clone_box(&self) -> Box<dyn CreatedWitnessData<WitnessType = Self::WitnessType>> {
        Box::new(self.clone())
    }

    fn logic_witness(
        &self,
        resource: Resource,
        resource_path: MerklePath,
        _config: &AnomaPayConfig,
    ) -> ProvingResult<Self::WitnessType> {
        Ok(TrivialLogicWitness::new(
            resource,
            resource_path,
            NullifierKey::default(),
            false,
        ))
    }
}
