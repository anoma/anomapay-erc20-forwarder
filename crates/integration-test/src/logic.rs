//! The shared AnomaPay ERC20 resource logic: the verifying key of its active circuit, and the
//! logic witness that consumes a persistent resource with the circuit that its logic ref names.

use anoma_pa_testkit::fixtures::identities::Keychain;
use anoma_pa_testkit::witness::LogicWitness;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::resource::Resource;
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;
use anomapay_erc20_library::TransferLogic;

/// Verifying key (image id) of the active token-transfer circuit, which every
/// created resource carries.
#[inline]
pub fn verifying_key() -> Digest {
    *anomapay_erc20_library::ANOMAPAY_ERC20_CIRCUIT_ID
}

/// The witness that consumes a persistent resource: for the legacy circuit if
/// the resource's logic ref names it, else for the active one.
pub(crate) fn consumed_persistent(
    resource: Resource,
    action_tree_root: Digest,
    owner: &Keychain,
    auth_sig: AuthoritySignature,
) -> Box<dyn LogicWitness> {
    if resource.logic_ref == *legacy_anomapay_erc20_library::TOKEN_TRANSFER_ID {
        return Box::new(
            legacy_anomapay_erc20_library::TransferLogic::consume_persistent_resource_logic(
                resource,
                action_tree_root,
                owner.nf_key.clone(),
                owner.auth_verifying_key(),
                owner.encryption_pk,
                auth_sig,
            ),
        );
    }
    Box::new(TransferLogic::consume_persistent_resource_logic(
        resource,
        action_tree_root,
        owner.nf_key.clone(),
        owner.auth_verifying_key(),
        owner.encryption_pk,
        auth_sig,
    ))
}

#[cfg(test)]
mod tests {
    use anoma_pa_testkit::fixtures::identities;
    use anoma_rm_risc0::action_tree::ActionTree;
    use anomapay_erc20_witness::{
        AUTH_SIGNATURE_DOMAIN, ValueInfo, calculate_persistent_value_ref,
    };

    use super::*;

    /// The witness that consumes alice's persistent resource carrying `logic_ref`.
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
        let action_tree_root = ActionTree::new(vec![resource.nullifier(&alice.nf_key)?]).root()?;
        let auth_sig = alice
            .auth_signing_key
            .sign(AUTH_SIGNATURE_DOMAIN, action_tree_root.as_bytes());
        Ok(consumed_persistent(
            resource,
            action_tree_root,
            &alice,
            auth_sig,
        ))
    }

    #[test]
    fn consumed_persistent_uses_the_legacy_circuit_for_a_legacy_resource() -> anyhow::Result<()> {
        let logic_ref = *legacy_anomapay_erc20_library::TOKEN_TRANSFER_ID;
        assert_ne!(
            logic_ref,
            verifying_key(),
            "the legacy circuit must not be the active circuit"
        );

        let witness = consumed_witness(logic_ref)?;

        assert_eq!(witness.verifying_key(), logic_ref);
        assert_eq!(
            witness.proving_key(),
            legacy_anomapay_erc20_library::TOKEN_TRANSFER_ELF
        );
        witness.constrain()?;
        Ok(())
    }

    #[test]
    fn consumed_persistent_uses_the_active_circuit_for_an_active_resource() -> anyhow::Result<()> {
        let witness = consumed_witness(verifying_key())?;

        assert_eq!(witness.verifying_key(), verifying_key());
        assert_eq!(
            witness.proving_key(),
            anomapay_erc20_library::ANOMAPAY_ERC20_CIRCUIT_ELF
        );
        witness.constrain()?;
        Ok(())
    }
}
