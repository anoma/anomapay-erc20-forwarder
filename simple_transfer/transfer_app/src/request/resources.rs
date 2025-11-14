use crate::request::witness_data::{ConsumedWitnessData, CreatedWitnessData};
use crate::request::ProvingError::{
    ConsumedResourceNotInActionTree, CreatedResourceNotInActionTree, InvalidSenderNullifierKey,
};
use crate::request::ProvingResult;
use crate::AnomaPayConfig;
use arm::action_tree::MerkleTree;
use arm::logic_proof::LogicProver;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::Digest;

//----------------------------------------------------------------------------
// Consumed Resource

/// `Consumed` holds all the data required to use a consumed resource in a
/// transaction. A `Consumed` struct contains the actual ARM resource, it's
/// nullifier key, and additional witness data to generate the proofs.
///
/// The witness data depends on which kind of resource this is.
pub struct Consumed<T> {
    /// The resource that is being consumed.
    pub resource: Resource,
    /// The nullifier key belonging to this resource.
    pub nullifier_key: NullifierKey,
    /// The witness data that is necessary to consume this resource.
    pub witness_data: Box<dyn ConsumedWitnessData<WitnessType = T>>,
}

impl<T: LogicProver + Send + 'static> Clone for Consumed<T> {
    //! To clone a resource the `witness_data` has to be cloned as well. Because
    //! this is a box we can't derive the default `Clone` trait and have to
    //! implement it manually.
    fn clone(&self) -> Self {
        Consumed {
            resource: self.resource,
            witness_data: self.witness_data.clone_box(),
            nullifier_key: self.nullifier_key.clone(),
        }
    }
}

impl<T: LogicProver + Send + 'static> Consumed<T> {
    /// Returns the nullifier for this consumed resource.
    ///
    /// The nullifier is computed using the resource and the nullifier key. If
    /// the nullifier key is not correct, this will fail.
    pub fn nullifier(&self) -> ProvingResult<Digest> {
        self.resource
            .nullifier(&self.nullifier_key)
            .map_err(|_e| InvalidSenderNullifierKey)
    }

    /// Compute the logic witness for this resource.
    pub fn logic_witness(
        &self,

        action_tree: &MerkleTree,
        config: &AnomaPayConfig,
    ) -> ProvingResult<T> {
        let nullifier = self.nullifier()?;
        let resource_path = action_tree
            .generate_path(&nullifier)
            .map_err(|_| ConsumedResourceNotInActionTree)?;

        let nullifier_key = NullifierKey::new(self.nullifier_key.inner());
        self.witness_data
            .logic_witness(self.resource, resource_path, nullifier_key, config)
    }
}

//----------------------------------------------------------------------------
// Created Resource

/// `Created` holds all the data require to use a created resource in a
/// transaction.
///
/// To create a resource you need the ARM resource, as well as witness data. The
/// witness data depends on which kind of resource this is.
pub struct Created<T> {
    /// The resource that is being created.
    pub resource: Resource,
    /// The witness data that is necessary to create this resource.
    pub witness_data: Box<dyn CreatedWitnessData<WitnessType = T>>,
}

impl<T: LogicProver + Send + 'static> Clone for Created<T> {
    //! To clone a resource the `witness_data` has to be cloned as well. Because
    //! this is a box we can't derive the default `Clone` trait and have to
    //! implement it manually.
    fn clone(&self) -> Self {
        Created {
            resource: self.resource,
            witness_data: self.witness_data.clone_box(),
        }
    }
}

impl<T: LogicProver + Send + 'static> Created<T> {
    /// The commitment of a created resource is the commitment of the underlying resource.
    pub fn commitment(&self) -> Digest {
        self.resource.commitment()
    }

    /// Compute the logic witness for this resource.
    pub fn logic_witness(
        &self,
        action_tree: &MerkleTree,
        config: &AnomaPayConfig,
    ) -> ProvingResult<T> {
        let resource_path = action_tree
            .generate_path(&self.commitment())
            .map_err(|_| CreatedResourceNotInActionTree)?;

        self.witness_data
            .logic_witness(self.resource, resource_path, config)
    }
}
