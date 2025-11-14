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

/// `Consumed` holds all the data required to use a consumed resource in a
/// transaction. A `Consumed` struct contains the actual ARM resource, it's
/// nullifier key, and additional witness data to generate the proofs.
///
/// The witness data depends on which kind of resource this is.
pub struct Consumed<T> {
    pub resource: Resource,
    pub nullifier_key: NullifierKey,
    pub witness_data: Box<dyn ConsumedWitnessData<WitnessType = T>>,
}

impl<T: LogicProver + Send + 'static> Clone for Consumed<T> {
    fn clone(&self) -> Self {
        Consumed {
            resource: self.resource,
            witness_data: self.witness_data.clone_box(),
            nullifier_key: self.nullifier_key.clone(),
        }
    }
}

impl<T: LogicProver + Send + 'static> Consumed<T> {
    pub fn nullifier(&self) -> ProvingResult<Digest> {
        self.resource
            .nullifier(&self.nullifier_key)
            .map_err(|_e| InvalidSenderNullifierKey)
    }

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

/// `Created` holds all the data require to use a created resource in a
/// transaction.
///
/// To create a resource you need the ARM resource, as well as witness data. The
/// witness data depends on which kind of resource this is.
pub struct Created<T> {
    pub resource: Resource,
    pub witness_data: Box<dyn CreatedWitnessData<WitnessType = T>>,
}

impl<T: LogicProver + Send + 'static> Clone for Created<T> {
    fn clone(&self) -> Self {
        Created {
            resource: self.resource,
            witness_data: self.witness_data.clone_box(),
        }
    }
}

impl<T: LogicProver + Send + 'static> Created<T> {
    pub fn commitment(&self) -> Digest {
        self.resource.commitment()
    }

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
