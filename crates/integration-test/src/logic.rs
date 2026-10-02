//! The shared anomapay-erc20 token-transfer resource logic: the verifying key
//! of its active circuit and the [`LogicWitness`] adapter over a circuit's
//! [`LogicProver`] that every action kind (wrap / transfer / unwrap) feeds to
//! the prover.

use anoma_pa_testkit::fixtures::identities::Keychain;
use anoma_pa_testkit::witness::LogicWitness;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::logic_instance::LogicInstance;
use anoma_rm_risc0::logic_proof::LogicProver;
use anoma_rm_risc0::resource::Resource;
use anoma_rm_risc0::resource_logic::LogicCircuit;
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;
use anyhow::Context;
use transfer_library::TransferLogic;
use transfer_witness::TokenTransferWitness;

/// Verifying key (image id) of the active token-transfer circuit, which every
/// created resource carries.
#[inline]
pub fn verifying_key() -> Digest {
    *transfer_library::TOKEN_TRANSFER_ID
}

/// Adapts a token-transfer circuit's [`LogicProver`] to the testkit's
/// [`LogicWitness`] trait.
pub(crate) struct Witness<L> {
    logic: L,
}

impl Witness<TransferLogic> {
    /// A witness for the active circuit.
    #[inline]
    pub(crate) fn new(witness: TokenTransferWitness) -> Self {
        Self {
            logic: TransferLogic { witness },
        }
    }
}

/// The witness that consumes a persistent resource: for 3.0.0-rc.2 if the
/// resource's logic ref names that circuit, else for the active one.
pub(crate) fn consumed_persistent(
    resource: Resource,
    action_tree_root: Digest,
    owner: &Keychain,
    auth_sig: AuthoritySignature,
) -> Box<dyn LogicWitness> {
    if resource.logic_ref == *transfer_library_3_0_0_rc_2::TOKEN_TRANSFER_ID {
        return Box::new(Witness {
            logic: transfer_library_3_0_0_rc_2::TransferLogic::consume_persistent_resource_logic(
                resource,
                action_tree_root,
                owner.nf_key.clone(),
                owner.auth_verifying_key(),
                owner.encryption_pk,
                auth_sig,
            ),
        });
    }
    Box::new(Witness {
        logic: TransferLogic::consume_persistent_resource_logic(
            resource,
            action_tree_root,
            owner.nf_key.clone(),
            owner.auth_verifying_key(),
            owner.encryption_pk,
            auth_sig,
        ),
    })
}

impl<L> LogicWitness for Witness<L>
where
    L: LogicProver,
    L::Witness: LogicCircuit,
{
    fn verifying_key(&self) -> Digest {
        L::verifying_key()
    }

    fn constrain(&self) -> anyhow::Result<LogicInstance> {
        self.logic
            .witness()
            .constrain()
            .map_err(anyhow::Error::from)
            .context("invalid transfer logic witness")
    }

    fn witness_to_vec(&self) -> anyhow::Result<Vec<u32>> {
        risc0_zkvm::serde::to_vec(self.logic.witness())
            .context("failed to serialize transfer logic witness to risc0 words")
    }

    fn proving_key(&self) -> Vec<u8> {
        L::proving_key().to_vec()
    }
}

#[cfg(test)]
mod tests {
    use anoma_pa_testkit::fixtures::identities;
    use anoma_rm_risc0::action_tree::ActionTree;
    use transfer_witness::{AUTH_SIGNATURE_DOMAIN, ValueInfo, calculate_persistent_value_ref};

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
    fn consumed_persistent_uses_the_3_0_0_rc_2_circuit_for_a_3_0_0_rc_2_resource()
    -> anyhow::Result<()> {
        let logic_ref = *transfer_library_3_0_0_rc_2::TOKEN_TRANSFER_ID;
        assert_ne!(
            logic_ref,
            verifying_key(),
            "3.0.0-rc.2 must not be the active circuit"
        );

        let witness = consumed_witness(logic_ref)?;

        assert_eq!(witness.verifying_key(), logic_ref);
        assert_eq!(
            witness.proving_key(),
            transfer_library_3_0_0_rc_2::TOKEN_TRANSFER_ELF
        );
        witness.constrain()?;
        Ok(())
    }

    #[test]
    fn consumed_persistent_uses_the_active_circuit_for_an_active_resource() -> anyhow::Result<()> {
        let witness = consumed_witness(verifying_key())?;

        assert_eq!(witness.verifying_key(), verifying_key());
        assert_eq!(witness.proving_key(), transfer_library::TOKEN_TRANSFER_ELF);
        witness.constrain()?;
        Ok(())
    }
}
