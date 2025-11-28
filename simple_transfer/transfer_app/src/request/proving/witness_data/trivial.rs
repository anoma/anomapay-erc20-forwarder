//! Trivial resources are resources that do not hold ERC20 tokens, but are used
//! to balance transactions. Resources used to balance transactions are called
//! "padding resources."

use crate::request::proving::witness_data::{ConsumedWitnessData, CreatedWitnessData, WitnessTypes};
use crate::request::proving::ProvingResult;
use crate::AnomaPayConfig;
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;
use arm::Digest;
use async_trait::async_trait;
use rocket::serde::{Deserialize, Serialize};
use utoipa::ToSchema;
//----------------------------------------------------------------------------
// Consumed Ephemeral Resource

/// The `ConsumedEphemeral` resource witness data holds all the information
/// necessary to consume an ephemeral resource.
///
/// An ephemeral resource is consumed in, for example, a split. The user splits
/// 1 resource into 2 resources. To balance the transaction a trivial consumed
/// ephemeral resource is created.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
#[schema(as=TrivialConsumedEphemeral)]
/// The empty witness data for consumed ephemeral resources.
pub struct ConsumedEphemeral {}

#[async_trait]
#[typetag::serde]
impl ConsumedWitnessData for ConsumedEphemeral {
    fn logic_witness(
        &self,
        resource: Resource,
        action_tree_root: Digest,
        nullifier_key: NullifierKey,
        _config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness = TrivialLogicWitness::new(resource, action_tree_root, nullifier_key, true);
        Ok(WitnessTypes::Trivial(Box::new(witness)))
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
// Created Ephemeral Resource

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
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
#[schema(as=TrivialCreatedEphemeral)]
pub struct CreatedEphemeral {}

#[typetag::serde]
impl CreatedWitnessData for CreatedEphemeral {
    fn logic_witness(
        &self,
        resource: Resource,
        action_tree_root: Digest,
        _config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        let witness =
            TrivialLogicWitness::new(resource, action_tree_root, NullifierKey::default(), false);

        Ok(WitnessTypes::Trivial(Box::new(witness)))
    }
}
