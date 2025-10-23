use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    ActionError, ActionTreeError, DeltaProofCreateError, InvalidKeyChain,
    InvalidNullifierSizeError, LogicProofCreateError, MerkleProofError,
};
use crate::evm::indexer::pa_merkle_path;
use crate::examples::burn::value_ref_ephemeral_burn;
use crate::examples::shared::{label_ref, random_nonce, verify_transaction};
use crate::examples::TOKEN_ADDRESS_SEPOLIA_USDC;
use crate::requests::{compliance_proof, logic_proof};
use crate::user::Keychain;
use crate::AnomaPayConfig;
use arm::action::Action;
use arm::action_tree::MerkleTree;
use arm::authorization::AuthorizationSignature;
use arm::compliance::ComplianceWitness;
use arm::delta_proof::DeltaWitness;
use arm::logic_proof::LogicProver;
use arm::resource::Resource;
use arm::transaction::{Delta, Transaction};
use arm::Digest;
use transfer_library::TransferLogic;

// these can be dead code because they're used for development.
#[allow(dead_code)]
pub async fn create_burn_transaction(
    burner: Keychain,
    burned_resource: Resource,
    config: &AnomaPayConfig,
) -> Result<(Resource, Transaction), TransactionError> {
    // to burn a resource, we need the nullifier of that resource.
    let burned_resource_nullifier = burned_resource
        .nullifier(&burner.nf_key)
        .map_err(|_| InvalidKeyChain)?;

    ////////////////////////////////////////////////////////////////////////////
    // Construct the ephemeral resource to create

    let nonce = burned_resource_nullifier
        .as_bytes()
        .try_into()
        .map_err(|_| InvalidNullifierSizeError)?;

    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: burned_resource.quantity,
        value_ref: value_ref_ephemeral_burn(&burner),
        is_ephemeral: true,
        nonce,
        nk_commitment: burner.nf_key.commit(),
        rand_seed: random_nonce(),
    };

    let created_resource_commitment = created_resource.commitment();

    ////////////////////////////////////////////////////////////////////////////
    // Create the action tree

    let action_tree: MerkleTree =
        MerkleTree::new(vec![burned_resource_nullifier, created_resource_commitment]);

    let action_tree_root: Digest = action_tree.root();

    ////////////////////////////////////////////////////////////////////////////
    // Create the permit signature

    let auth_signature: AuthorizationSignature =
        burner.auth_signing_key.sign(action_tree_root.as_bytes());

    ////////////////////////////////////////////////////////////////////////////
    // Get the merkle proof for the resource being transferred

    let burned_resource_commitment = burned_resource.commitment();

    let merkle_proof = pa_merkle_path(config, burned_resource_commitment)
        .await
        .map_err(|_| MerkleProofError)?;

    ////////////////////////////////////////////////////////////////////////////
    // Create compliance proof

    let compliance_witness = ComplianceWitness::from_resources_with_path(
        burned_resource,
        burner.nf_key.clone(),
        merkle_proof,
        created_resource,
    );

    // generate the proof in a separate thread
    let compliance_unit_future = compliance_proof(&compliance_witness);
    let compliance_unit = compliance_unit_future.await?;

    ////////////////////////////////////////////////////////////////////////////
    // Create logic proof

    let created_resource_path = action_tree
        .generate_path(&created_resource_commitment)
        .map_err(|_| ActionTreeError)?;

    let burned_resource_path = action_tree
        .generate_path(&burned_resource_nullifier)
        .map_err(|_| ActionTreeError)?;

    let created_logic_witness: TransferLogic = TransferLogic::consume_persistent_resource_logic(
        burned_resource,
        burned_resource_path,
        burner.nf_key.clone(),
        burner.auth_verifying_key(),
        auth_signature,
    );

    // generate the proof in a separate thread
    // this is due to bonsai being non-blocking or something. there is a feature flag for bonsai
    // that allows it to be non-blocking or vice versa, but this is to figure out.
    let created_logic_proof_future = logic_proof(&created_logic_witness);
    let created_logic_proof = created_logic_proof_future.await?;

    let burned_logic_witness: TransferLogic = TransferLogic::burn_resource_logic(
        created_resource,
        created_resource_path,
        config.forwarder_address.to_vec(),
        TOKEN_ADDRESS_SEPOLIA_USDC.to_vec(),
        burner.evm_address.to_vec(),
    );

    let burned_logic_proof_future = logic_proof(&burned_logic_witness);
    let burned_logic_proof = burned_logic_proof_future.await?;

    ////////////////////////////////////////////////////////////////////////////
    // Create actions for transaction

    let action: Action = Action::new(
        vec![compliance_unit],
        vec![burned_logic_proof, created_logic_proof],
    )
    .map_err(|_| ActionError)?;

    let delta_witness =
        DeltaWitness::from_bytes(&compliance_witness.rcv).map_err(|_| LogicProofCreateError)?;
    let transaction = Transaction::create(vec![action], Delta::Witness(delta_witness));
    let transaction = transaction
        .generate_delta_proof()
        .map_err(|_| DeltaProofCreateError)?;

    verify_transaction(transaction.clone())?;
    Ok((created_resource, transaction))
}
