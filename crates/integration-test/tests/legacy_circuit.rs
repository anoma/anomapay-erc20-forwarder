//! Checks the legacy circuit: a consumed persistent resource gets it if its logic ref names it, and
//! the active circuit otherwise.

use anoma_pa_testkit::fixtures::{action, identities};
use anoma_pa_testkit::witness::LogicWitness;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_forwarder_integration_test::fixtures::persistent;
use anomapay_erc20_forwarder_integration_test::logic::{self, legacy};
use anomapay_erc20_witness::{ValueInfo, calculate_persistent_value_ref};

/// The logic witness of alice's persistent resource carrying `logic_ref`, consumed in an action of
/// its own.
fn consumed_witness(logic_ref: Digest) -> anyhow::Result<Box<dyn LogicWitness>> {
    let alice = identities::alice()?;
    let resource = Resource {
        logic_ref,
        label_ref: Digest::default(),
        quantity: 1,
        value_ref: calculate_persistent_value_ref(&ValueInfo {
            auth_pk: alice.auth_verifying_key(),
            encryption_pk: alice.encryption_pk,
        }),
        is_ephemeral: false,
        nonce: [0; 32],
        nk_commitment: alice.nf_key.commit(),
        rand_seed: [0; 32],
    };
    let mut action = action::build([persistent::consumed(
        &alice,
        resource,
        MerklePath::empty(),
        None,
    )])?;
    Ok(action.logic_witnesses.remove(0))
}

#[test]
fn persistent_consumed_uses_the_legacy_circuit_for_a_legacy_resource() -> anyhow::Result<()> {
    let logic_ref = legacy::verifying_key();
    assert_ne!(
        logic_ref,
        logic::verifying_key(),
        "the legacy circuit must not be the active circuit"
    );

    let witness = consumed_witness(logic_ref)?;

    assert_eq!(witness.verifying_key(), logic_ref);
    assert_eq!(
        risc0_zkvm::compute_image_id(&witness.proving_key())?,
        logic_ref,
        "the image id of the legacy binary is the legacy logic ref"
    );
    witness.constrain()?;
    Ok(())
}

#[test]
fn persistent_consumed_uses_the_active_circuit_for_an_active_resource() -> anyhow::Result<()> {
    let witness = consumed_witness(logic::verifying_key())?;

    assert_eq!(witness.verifying_key(), logic::verifying_key());
    assert_eq!(
        witness.proving_key(),
        anomapay_erc20_library::ANOMAPAY_ERC20_CIRCUIT_ELF
    );
    witness.constrain()?;
    Ok(())
}
