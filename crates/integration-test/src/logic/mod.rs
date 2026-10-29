//! The shared AnomaPay ERC20 resource logic: the verifying key of its active circuit, and the
//! logic witness that consumes a persistent resource with the circuit that its logic ref names.
//! [`legacy`] holds the legacy circuit.

pub mod legacy;

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
    let is_legacy = resource.logic_ref == legacy::verifying_key();
    let logic = TransferLogic::consume_persistent_resource_logic(
        resource,
        action_tree_root,
        owner.nf_key.clone(),
        owner.auth_verifying_key(),
        owner.encryption_pk,
        auth_sig,
    );
    if is_legacy {
        Box::new(legacy::Witness(logic))
    } else {
        Box::new(logic)
    }
}
