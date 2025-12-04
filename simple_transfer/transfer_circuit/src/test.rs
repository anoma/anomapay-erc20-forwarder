// Add circuit tests here
use arm::{logic_proof::LogicProver, nullifier_key::NullifierKey, resource::Resource};
use arm_gadgets::{
    authorization::{AuthorizationSigningKey, AuthorizationVerifyingKey},
    encryption::{generate_public_key, SecretKey},
};
use transfer_library::TransferLogic;
use transfer_witness::{
    calculate_label_ref, calculate_persistent_value_ref, calculate_value_ref_from_ethereum_account_addr,
    ValueInfo,
};

const FORWARDER_ADDR: [u8; 20] = [0u8; 20];
const ERC20_ADDR: [u8; 20] = [1u8; 20];
const USER_ADDR: [u8; 20] = [2u8; 20];
const QUANTITY: u128 = 1000;
const NF_KEY_BYTES: [u8; 32] = [3u8; 32];
const PERMIT_NONCE: [u8; 32] = [4u8; 32];
const PERMIT_DEADLINE: [u8; 32] = [5u8; 32];
const PERMIT_SIG: [u8; 65] = [6u8; 65];
const AUTH_SK: [u8; 32] = [7u8; 32];

// Create a sample ephemeral resource for testing
fn create_ephemeral_resource() -> Resource {
    let label_ref = calculate_label_ref(&FORWARDER_ADDR, &ERC20_ADDR);
    let value_ref = calculate_value_ref_from_ethereum_account_addr(&USER_ADDR);
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

// Create a sample persistent resource for testing
fn create_persistent_resource() -> Resource {
    let label_ref = calculate_label_ref(&FORWARDER_ADDR, &ERC20_ADDR);
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
        logic_ref: TransferLogic::verifying_key(),
        label_ref,
        value_ref,
        quantity: QUANTITY,
        is_ephemeral: false,
        nk_commitment,
        ..Default::default()
    }
}

#[test]
fn test_mint() {
    use arm::proving_system::ProofType;
    use arm::Digest;

    let resource = create_ephemeral_resource();
    let resource_logic = TransferLogic::mint_resource_logic_with_permit(
        resource,
        Digest::default(), // dummy action_tree_root
        NullifierKey::from_bytes(NF_KEY_BYTES),
        FORWARDER_ADDR.to_vec(),
        ERC20_ADDR.to_vec(),
        USER_ADDR.to_vec(),
        PERMIT_NONCE.to_vec(),
        PERMIT_DEADLINE.to_vec(),
        PERMIT_SIG.to_vec(),
    );

    let proof = resource_logic.prove(ProofType::Succinct).unwrap();

    proof.verify().unwrap();
}

#[test]
fn test_burn() {
    use arm::proving_system::ProofType;
    use arm::Digest;

    let resource = create_ephemeral_resource();
    let resource_logic = TransferLogic::burn_resource_logic(
        resource,
        Digest::default(), // dummy action_tree_root
        FORWARDER_ADDR.to_vec(),
        ERC20_ADDR.to_vec(),
        USER_ADDR.to_vec(),
    );

    let proof = resource_logic.prove(ProofType::Succinct).unwrap();

    proof.verify().unwrap();
}

#[test]
fn test_transfer() {
    use arm::proving_system::ProofType;
    use arm::Digest;
    use arm_gadgets::encryption::{random_keypair, Ciphertext};
    use transfer_witness::{ResourceWithLabel, AUTH_SIGNATURE_DOMAIN};

    let consumed_resource = create_persistent_resource();

    let auth_sk = AuthorizationSigningKey::from_bytes(&AUTH_SK).unwrap();
    let auth_pk = AuthorizationVerifyingKey::from_signing_key(&auth_sk);
    let encryption_sk = SecretKey::default();
    let encryption_pk = generate_public_key(&encryption_sk.inner());

    let action_tree_root = Digest::default(); // dummy action_tree_root

    let auth_sig = auth_sk.sign(AUTH_SIGNATURE_DOMAIN, action_tree_root.as_bytes());

    let consumed_resource_logic = TransferLogic::consume_persistent_resource_logic(
        consumed_resource,
        action_tree_root,
        NullifierKey::from_bytes(NF_KEY_BYTES),
        auth_pk,
        encryption_pk,
        auth_sig,
    );

    let proof = consumed_resource_logic.prove(ProofType::Succinct).unwrap();
    proof.verify().unwrap();

    let created_resource = create_persistent_resource();
    let (created_discovery_sk, created_discovery_pk) = random_keypair();
    let created_resource_logic = TransferLogic::create_persistent_resource_logic(
        created_resource,
        action_tree_root,
        &created_discovery_pk,
        auth_pk,
        encryption_pk,
        FORWARDER_ADDR.to_vec(),
        ERC20_ADDR.to_vec(),
    );

    let proof = created_resource_logic.prove(ProofType::Succinct).unwrap();
    proof.verify().unwrap();

    // check discovery ciphertext
    let discovery_ciphertext =
        Ciphertext::from_words(&proof.get_instance().unwrap().app_data.discovery_payload[0].blob);
    discovery_ciphertext.decrypt(&created_discovery_sk).unwrap();

    // check encryption
    let encryption_ciphertext =
        Ciphertext::from_words(&proof.get_instance().unwrap().app_data.resource_payload[0].blob);
    let plaintext = encryption_ciphertext.decrypt(&encryption_sk).unwrap();
    let expected_plaintext = bincode::serialize(&ResourceWithLabel {
        resource: created_resource,
        forwarder: FORWARDER_ADDR.to_vec(),
        token: ERC20_ADDR.to_vec(),
    })
    .unwrap();
    assert_eq!(plaintext.as_bytes(), expected_plaintext);
}
