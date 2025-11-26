use crate::request::witness_data::{ConsumedWitnessData, CreatedWitnessData, WitnessTypes};
use crate::request::ProvingError::InvalidNullifierKey;
use crate::request::ProvingResult;
use crate::web;
use crate::web::serializer::serialize_nullifier_key;
use crate::web::serializer::serialize_resource;
use crate::web::serializer::SerializedResource;
use crate::AnomaPayConfig;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::Digest;
use enum_dispatch::enum_dispatch;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// This enum holds all the possible structs for created resource witnesses.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
#[enum_dispatch(CreatedWitnessData)]
pub enum CreatedWitnessDataEnum {
    Persistent(crate::request::witness_data::token_transfer::CreatedPersistent),
    Ephemeral(crate::request::witness_data::token_transfer::CreatedEphemeral),
    TrivialEphemeral(crate::request::witness_data::trivial::CreatedEphemeral),
}

/// This enum holds all the possible values for consumed resource witnesses.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
#[enum_dispatch(ConsumedWitnessData)]
pub enum ConsumedWitnessDataEnum {
    Persistent(crate::request::witness_data::token_transfer::ConsumedPersistent),
    Ephemeral(crate::request::witness_data::token_transfer::ConsumedEphemeral),
    TrivialEphemeral(crate::request::witness_data::trivial::ConsumedEphemeral),
}

//----------------------------------------------------------------------------
// Consumed Resource

/// `Consumed` holds all the data required to use a consumed resource in a
/// transaction. A `Consumed` struct contains the actual ARM resource, it's
/// nullifier key, and additional witness data to generate the proofs.
///
/// The witness data depends on which kind of resource this is.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
pub struct Consumed {
    #[serde(with = "serialize_resource")]
    #[schema(value_type = SerializedResource)]
    /// The resource that is being consumed.
    pub resource: Resource,
    #[schema(value_type = String, format = Binary)]
    #[serde(with = "serialize_nullifier_key")]
    /// The nullifier key belonging to this resource.
    pub nullifier_key: NullifierKey,
    #[schema(value_type = web::ConsumedWitnessDataSchema)]
    /// The witness data that is necessary to consume this resource.
    pub witness_data: ConsumedWitnessDataEnum,
}

impl Consumed {
    /// Returns the nullifier for this consumed resource.
    ///
    /// The nullifier is computed using the resource and the nullifier key. If
    /// the nullifier key is not correct, this will fail.
    pub fn nullifier(&self) -> ProvingResult<Digest> {
        self.resource
            .nullifier(&self.nullifier_key)
            .map_err(|_e| InvalidNullifierKey)
    }

    /// Compute the logic witness for this resource.
    pub fn logic_witness(
        &self,
        action_tree_root: Digest,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        self.witness_data.logic_witness(
            self.resource,
            action_tree_root,
            self.nullifier_key.clone(),
            config,
        )
    }
}

//----------------------------------------------------------------------------
// Created Resource

/// `Created` holds all the data require to use a created resource in a
/// transaction.
///
/// To create a resource you need the ARM resource, as well as witness data. The
/// witness data depends on which kind of resource this is.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
pub struct Created {
    /// The resource that is being created.
    #[serde(with = "serialize_resource")]
    #[schema(value_type = SerializedResource, rename="Resource")]
    pub resource: Resource,
    #[schema(value_type = web::CreatedWitnessDataSchema)]
    /// The witness data that is necessary to create this resource.
    pub witness_data: CreatedWitnessDataEnum,
}

impl Created {
    /// The commitment of a created resource is the commitment of the underlying resource.
    pub fn commitment(&self) -> Digest {
        self.resource.commitment()
    }

    /// Compute the logic witness for this resource.
    pub fn logic_witness(
        &self,
        action_tree_root: Digest,
        config: &AnomaPayConfig,
    ) -> ProvingResult<WitnessTypes> {
        self.witness_data
            .logic_witness(self.resource, action_tree_root, config)
    }
}
