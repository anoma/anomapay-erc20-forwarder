// Add circuit tests here
use arm::{logic_proof::LogicProver, nullifier_key::NullifierKey, resource::Resource};
use arm_gadgets::{
    authorization::{AuthorizationSigningKey, AuthorizationVerifyingKey},
    encryption::{generate_public_key, SecretKey},
};
use transfer_library::TransferLogic;
use transfer_library_v2::TransferLogicV2;
use transfer_witness::{
    calculate_label_ref, calculate_persistent_value_ref, calculate_value_ref_from_user_addr,
    ValueInfo,
};

const FORWARDER_ADDR_V1: [u8; 20] = [0u8; 20];
const FORWARDER_ADDR_V2: [u8; 20] = [10u8; 20];
const ERC20_ADDR: [u8; 20] = [1u8; 20];
const USER_ADDR: [u8; 20] = [2u8; 20];
const QUANTITY: u128 = 1000;
const NF_KEY_BYTES: [u8; 32] = [3u8; 32];
const AUTH_SK: [u8; 32] = [7u8; 32];

// Create a sample ephemeral resource in v2 for testing
fn create_ephemeral_resource_v2() -> Resource {
    let label_ref = calculate_label_ref(&FORWARDER_ADDR_V2, &ERC20_ADDR);
    let value_ref = calculate_value_ref_from_user_addr(&USER_ADDR);
    let nk_commitment = NullifierKey::from_bytes(NF_KEY_BYTES).commit();

    Resource {
        logic_ref: TransferLogic::verifying_key(),
        nk_commitment,
        label_ref,
        value_ref,
        quantity: QUANTITY,
        is_ephemeral: true,
        ..Default::default()
    }
}

// Create a sample persistent resource in v1 for testing
fn create_persistent_resource_v1() -> Resource {
    let label_ref = calculate_label_ref(&FORWARDER_ADDR_V1, &ERC20_ADDR);
    let nk_commitment = NullifierKey::from_bytes(NF_KEY_BYTES).commit();
    let auth_sk = AuthorizationSigningKey::from_bytes(&AUTH_SK).unwrap();
    let auth_pk = AuthorizationVerifyingKey::from_signing_key(&auth_sk);
    let encryption_sk = SecretKey::default();
    let encryption_pk = generate_public_key(&encryption_sk.inner());
    let value_info = ValueInfo {
        auth_pk,
        encryption_pk,
    };

    let value_ref = calculate_persistent_value_ref(&value_info);

    Resource {
        logic_ref: TransferLogicV2::verifying_key(),
        label_ref,
        value_ref,
        quantity: QUANTITY,
        is_ephemeral: false,
        nk_commitment,
        ..Default::default()
    }
}

#[test]
fn test_migrate() {
    use arm::merkle_path::MerklePath;
    use arm::proving_system::ProofType;
    use arm::Digest;
    use transfer_witness_v2::AUTH_SIGNATURE_DOMAIN_V2;

    // mock a resource to be migrated in v1
    let migrated_resource = create_persistent_resource_v1();

    // create the ephemeral resource in v2 to migrate the migrated_resource
    let self_resource = create_ephemeral_resource_v2();

    // It should be the real root in practice
    let action_tree_root = Digest::default();

    let nf_key = NullifierKey::from_bytes(NF_KEY_BYTES);

    let migrated_auth_sk = AuthorizationSigningKey::from_bytes(&AUTH_SK).unwrap();
    let migrated_auth_pk = AuthorizationVerifyingKey::from_signing_key(&migrated_auth_sk);

    let encryption_sk = SecretKey::default();
    let migrated_encryption_pk = generate_public_key(&encryption_sk.inner());

    let migrated_auth_sig =
        migrated_auth_sk.sign(AUTH_SIGNATURE_DOMAIN_V2, action_tree_root.as_bytes());

    let resource_logic = TransferLogicV2::migrate_resource_logic(
        self_resource,
        action_tree_root,
        nf_key.clone(),
        FORWARDER_ADDR_V2.to_vec(),
        ERC20_ADDR.to_vec(),
        USER_ADDR.to_vec(),
        migrated_resource,
        nf_key,                // using the same nf_key for simplicity
        MerklePath::default(), // using default path for simplicity, only a real tx needs a valid path
        migrated_auth_pk,
        migrated_encryption_pk,
        migrated_auth_sig,
        FORWARDER_ADDR_V1.to_vec(),
    );

    let proof = resource_logic.prove(ProofType::Succinct).unwrap();

    proof.verify().unwrap();
}
