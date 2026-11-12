//! The resources of the draft emergency migrating ERC20 forwarder, which replaces the ERC20 forwarder after a flaw in
//! the ERC20 circuit. [`persistent`] and [`ephemeral`] mirror the ERC20 resources with the emergency migrating
//! circuit. A [`migrate`] resource moves resources with a vulnerable logic ref into resources of the emergency
//! migrating circuit.

pub mod ephemeral;
pub mod migrate;
pub mod persistent;

use anoma_rm_risc0::Digest;

/// Verifying key (image id) of the emergency migrating circuit, which every resource of this module carries.
#[inline]
pub fn verifying_key() -> Digest {
    *anomapay_emergency_migrating_erc20_library::ANOMAPAY_EMERGENCY_MIGRATING_ERC20_CIRCUIT_ID
}
