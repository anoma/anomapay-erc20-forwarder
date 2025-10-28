use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    ActionError, ComplianceUnitCreateError, DeltaProofCreateError, InvalidAmount, InvalidKeyChain,
    InvalidNullifierSizeError, LogicProofCreateError, MerklePathError, MerkleProofError,
};
use crate::evm::indexer::pa_merkle_path;
use crate::examples::burn::value_ref_ephemeral_burn;
use crate::examples::end_to_end::burn::create_burn_transaction;
use crate::examples::end_to_end::split::create_split_transaction;
use crate::examples::shared::{label_ref, random_nonce, value_ref_created, verify_transaction};
use crate::examples::TOKEN_ADDRESS_SEPOLIA_USDC;
use crate::user::Keychain;
use crate::AnomaPayConfig;
use arm::action::Action;
use arm::action_tree::MerkleTree;
use arm::authorization::AuthorizationSignature;
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::delta_proof::DeltaWitness;
use arm::logic_proof::LogicProver;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;
use arm::transaction::{Delta, Transaction};
use arm::Digest;
use std::thread;
use transfer_library::TransferLogic;

// these can be dead code because they're used for development.
#[allow(dead_code)]
pub async fn create_general_transfer_transaction(
    sender: Keychain,
    maybe_receiver: Option<Keychain>,
    to_send_resources: Vec<Resource>,
    amount: u128,
    config: &AnomaPayConfig,
) -> Result<(Resource, Option<Resource>, Transaction), TransactionError> {
    let label = to_send_resources[0].label_ref;
    let nullifier_key_commitment = to_send_resources[0].nk_commitment;
    // compute total amount of given resource
    let total_send_quantity = to_send_resources.iter().fold(0, |acc, r| {
        if r.logic_ref == TransferLogic::verifying_key()
            && r.label_ref == label
            && r.nk_commitment == nullifier_key_commitment
        {
            acc + r.quantity
        } else {
            // if the spent resources are of different kinds, then throw an error
            panic!("Spent resources do not have the same kind or nullifier key");
        }
    });

    // ensure the amount is enough to split
    if total_send_quantity <= amount {
        return Err(InvalidAmount);
    };

    // error if sending out 0 resources
    if amount == 0 {
        panic!("Trying to send 0 resources");
    };

    if to_send_resources.len() == 1 {
        match maybe_receiver {
            // If only one exact resource to send, then it is a usual transfer
            Some(receiver) => {
                create_split_transaction(sender, receiver, to_send_resources[0], amount, config)
                    .await
            }

            // If no receiver present then burn
            None => {
                let (ephemeral_created, tx) =
                    create_burn_transaction(sender, to_send_resources[0], config).await?;

                Ok((ephemeral_created, None, tx))
            }
        }
    } else {
        let remainder = total_send_quantity - amount;

        let padding_resource = Resource {
            logic_ref: TrivialLogicWitness::verifying_key(),
            label_ref: Digest::default(),
            quantity: 0,
            value_ref: Digest::default(),
            is_ephemeral: true,
            nonce: random_nonce(),
            nk_commitment: NullifierKey::default().commit(),
            rand_seed: [0u8; 32],
        };

        let first_resource_nullifier = to_send_resources[0]
            .nullifier(&sender.nf_key)
            .map_err(|_| InvalidKeyChain)?;

        let second_resource_nullifier = to_send_resources[1]
            .nullifier(&sender.nf_key)
            .map_err(|_| InvalidKeyChain)?;

        ////////////////////////////////////////////////////////////////////////////
        // Construct the resource for the receiver

        let nonce = first_resource_nullifier
            .as_bytes()
            .try_into()
            .map_err(|_| InvalidNullifierSizeError)?;

        let created_resource = match &maybe_receiver {
            // If some reveiver is present, we create a resource for them
            Some(receiver) => Resource {
                logic_ref: TransferLogic::verifying_key(),
                label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
                quantity: amount,
                value_ref: value_ref_created(&receiver),
                is_ephemeral: false,
                nonce,
                nk_commitment: receiver.nf_key.commit(),
                rand_seed: [7u8; 32],
            },
            // If no receiver is present, we are burning
            None => Resource {
                logic_ref: TransferLogic::verifying_key(),
                label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
                quantity: amount,
                value_ref: value_ref_ephemeral_burn(&sender),
                is_ephemeral: true,
                nonce,
                nk_commitment: nullifier_key_commitment,
                rand_seed: random_nonce(),
            },
        };

        let created_resource_commitment = created_resource.commitment();

        ////////////////////////////////////////////////////////////////////////////
        // Construct the remainder resource

        let nonce = second_resource_nullifier
            .as_bytes()
            .try_into()
            .map_err(|_| InvalidNullifierSizeError)?;

        let remainder_resource: Resource = if remainder == 0 {
            // If remainder is 0, generate a trivial resource
            // for optimization purposes
            Resource {
                nonce,
                ..padding_resource
            }
        } else {
            Resource {
                quantity: remainder,
                nonce,
                ..to_send_resources[0]
            }
        };

        let remainder_resource_commitment = remainder_resource.commitment();

        ////////////////////////////////////////////////////////////////////////////
        // Construct the rest of the created resources and populate tree leaves

        let mut created_resources = vec![created_resource, remainder_resource];

        let mut leaves = vec![
            first_resource_nullifier,
            created_resource.commitment(),
            second_resource_nullifier,
            remainder_resource.commitment(),
        ];

        for (index, consumed_res) in to_send_resources.iter().enumerate() {
            if index >= 2 {
                let created_nonce = consumed_res
                    .nullifier(&sender.nf_key)
                    .map_err(|_| InvalidKeyChain)?
                    .as_bytes()
                    .try_into()
                    .map_err(|_| InvalidNullifierSizeError)?;
                let created_padding_resource = Resource {
                    nonce: created_nonce,
                    ..padding_resource
                };

                created_resources.push(created_padding_resource);
                let nullifier = consumed_res
                    .nullifier(&sender.nf_key)
                    .map_err(|_| InvalidKeyChain)?;
                leaves.push(nullifier);
                let commitment = created_padding_resource.commitment();
                leaves.push(commitment);
            };
        }

        ////////////////////////////////////////////////////////////////////////////
        // Create the action tree

        let action_tree: MerkleTree = MerkleTree::new(leaves.clone());

        ////////////////////////////////////////////////////////////////////////////
        // Create the permit signature

        let action_tree_root: Digest = action_tree.root();
        let auth_signature: AuthorizationSignature =
            sender.auth_signing_key.sign(action_tree_root.as_bytes());

        ////////////////////////////////////////////////////////////////////////////
        // Create compliance units

        let mut compliance_units = vec![];

        // Generate randomness commitments alongside
        let mut randomness_commitments = vec![];

        for (index, consumed_resource) in to_send_resources.iter().enumerate() {
            let path = pa_merkle_path(config, consumed_resource.commitment())
                .await
                .map_err(|_| MerkleProofError)?;

            let witness = ComplianceWitness::from_resources_with_path(
                consumed_resource.clone(),
                sender.nf_key.clone(),
                path,
                created_resources[index],
            );

            randomness_commitments.push(witness.clone().rcv);

            let unit = thread::spawn(move || ComplianceUnit::create(&witness))
                .join()
                .map_err(|e| {
                    println!("prove thread panic: {:?}", e);
                    ComplianceUnitCreateError
                })?
                .map_err(|e| {
                    println!("proving error: {:?}", e);
                    ComplianceUnitCreateError
                })?;

            compliance_units.push(unit);
        }

        ////////////////////////////////////////////////////////////////////////////
        // Create logic proofs

        let mut consumed_resource_proofs = vec![];

        for (index, consumed_resource) in to_send_resources.iter().enumerate() {
            let consumed_resource_path = action_tree
                .generate_path(&(leaves[index * 2].clone()))
                .map_err(|_| MerklePathError)?;

            let witness = TransferLogic::consume_persistent_resource_logic(
                consumed_resource.clone(),
                consumed_resource_path.clone(),
                sender.nf_key.clone(),       //TODO ! // sender_nf_key.clone(),
                sender.auth_verifying_key(), //TODO ! // sender_verifying_key,
                auth_signature,
            );

            let proof = thread::spawn(move || witness.prove())
                .join()
                .map_err(|e| {
                    println!("prove thread panic: {:?}", e);
                    LogicProofCreateError
                })?
                .map_err(|e| {
                    println!("proving error: {:?}", e);
                    LogicProofCreateError
                })?;

            consumed_resource_proofs.push(proof);
        }

        //--------------------------------------------------------------------------
        // created proof

        let created_resource_path = action_tree
            .generate_path(&created_resource_commitment)
            .map_err(|_| MerklePathError)?;

        let created_logic_witness = match &maybe_receiver {
            Some(receiver) => TransferLogic::create_persistent_resource_logic(
                created_resource,
                created_resource_path,
                &receiver.discovery_pk,
                receiver.encryption_pk,
            ),
            None => TransferLogic::burn_resource_logic(
                created_resource,
                created_resource_path,
                config.forwarder_address.to_vec(),
                TOKEN_ADDRESS_SEPOLIA_USDC.to_vec(),
                sender.evm_address.to_vec(),
            ),
        };

        let created_logic_proof = thread::spawn(move || created_logic_witness.prove())
            .join()
            .map_err(|e| {
                println!("prove thread panic: {:?}", e);
                LogicProofCreateError
            })?
            .map_err(|e| {
                println!("proving error: {:?}", e);
                LogicProofCreateError
            })?;

        //--------------------------------------------------------------------------
        // remainder proof

        let remainder_resource_path = action_tree
            .generate_path(&remainder_resource_commitment)
            .map_err(|_| MerklePathError)?;

        let remainder_logic_proof = if remainder_resource.is_ephemeral {
            let remainder_logic_witness = TrivialLogicWitness::new(
                remainder_resource,
                remainder_resource_path,
                NullifierKey::default(),
                false,
            );
            thread::spawn(move || remainder_logic_witness.prove())
                .join()
                .map_err(|e| {
                    println!("prove thread panic: {:?}", e);
                    LogicProofCreateError
                })?
                .map_err(|e| {
                    println!("proving error: {:?}", e);
                    LogicProofCreateError
                })?
        } else {
            let remainder_logic_witness = TransferLogic::create_persistent_resource_logic(
                remainder_resource,
                remainder_resource_path,
                &sender.discovery_pk,
                sender.encryption_pk,
            );

            thread::spawn(move || remainder_logic_witness.prove())
                .join()
                .map_err(|e| {
                    println!("prove thread panic: {:?}", e);
                    LogicProofCreateError
                })?
                .map_err(|e| {
                    println!("proving error: {:?}", e);
                    LogicProofCreateError
                })?
        };

        //-------------------------------------------------------------------------
        // Generate the rest of the proofs:

        let mut created_resource_proofs = vec![created_logic_proof, remainder_logic_proof];

        for (index, created_resource) in created_resources.iter().enumerate() {
            if index >= 2 {
                let created_resource_path = action_tree
                    .generate_path(&created_resource.commitment())
                    .map_err(|_| MerklePathError)?;

                let witness = TrivialLogicWitness::new(
                    *created_resource,
                    created_resource_path.clone(),
                    NullifierKey::default(),
                    false,
                );

                let proof = thread::spawn(move || witness.prove())
                    .join()
                    .map_err(|e| {
                        println!("prove thread panic: {:?}", e);
                        LogicProofCreateError
                    })?
                    .map_err(|e| {
                        println!("proving error: {:?}", e);
                        LogicProofCreateError
                    })?;

                created_resource_proofs.push(proof);
            }
        }

        //-----------------------------------------------------------------------
        // Collect all proofs

        let mut proofs = vec![];

        for (index, nullifier_proof) in consumed_resource_proofs.iter().enumerate() {
            // Push consumed resource proof
            proofs.push(nullifier_proof.clone());
            // Push created resource proof
            proofs.push(created_resource_proofs[index].clone());
        }

        ////////////////////////////////////////////////////////////////////////////
        // Create actions for transaction

        let action: Action = Action::new(compliance_units, proofs).map_err(|_| ActionError)?;

        let delta_witness: DeltaWitness = DeltaWitness::from_bytes_vec(&randomness_commitments)
            .map_err(|_| LogicProofCreateError)?;

        let transaction = Transaction::create(vec![action], Delta::Witness(delta_witness));

        let transaction = transaction
            .generate_delta_proof()
            .map_err(|_| DeltaProofCreateError)?;
        verify_transaction(transaction.clone())?;

        Ok((created_resource, Some(remainder_resource), transaction))
    }
}
