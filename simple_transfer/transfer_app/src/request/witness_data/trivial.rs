use crate::request::witness_data::{ConsumedWitnessData, CreatedWitnessData};
use crate::request::ProvingResult;
use crate::AnomaPayConfig;
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;

//----------------------------------------------------------------------------
// Consumed Ephemeral Resource

/// The `ConsumedEphemeral` resource witness data holds all the information
/// necessary to consume an ephemeral resource.
///
/// An ephemeral resource is consumed in, for example, a split. The user splits
/// 1 resource into 2 resources. To balance the transaction a trivial consumed
/// ephemeral resource is created.
#[derive(Clone)]
#[allow(dead_code)]
/// The empty witness data for consumed ephemeral resources.
struct ConsumedEphemeral {}

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

//----------------------------------------------------------------------------
// Created Ephemeral Resource

#[derive(Clone)]
#[allow(dead_code)]
/// The `CreatedEphemeral` resource witness data holds all the information to
/// consume an ephemeral trivial resource.
///
/// An ephemeral trivial resource is consumed in, for example, a burn
/// transaction. If the user wants to withdraw 2 resources, 2 token transfer
/// resources are consumed. There is only 1 token_transfer function generated
/// which holds the total amount of withdrawn tokens. To balance the
/// transaction, a trivial created resource is added.
///
///
/// These resources have no witness data associated with them, so the struct is
/// empty.
struct CreatedEphemeral {}

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
