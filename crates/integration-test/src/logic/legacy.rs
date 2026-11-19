//! The legacy circuit, which the legacy forwarders accept. It takes the witness of the active
//! circuit, so only its binary and its logic ref differ.

use alloy::primitives::{B256, b256};
use anoma_pa_testkit::witness::LogicWitness;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::logic_instance::LogicInstance;
use anomapay_erc20_library::TransferLogic;

/// Guest binary of the legacy circuit.
const ELF: &[u8] = include_bytes!("../../elf/legacy-anomapay-erc20-circuit-guest.bin");

/// Logic ref of the legacy circuit, which the legacy forwarders accept.
const LOGIC_REF: B256 = b256!("bc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad");

/// Verifying key (image id) of the legacy circuit.
pub fn verifying_key() -> Digest {
    Digest::from_bytes(LOGIC_REF.0)
}

/// A witness of the active circuit that the legacy circuit proves.
pub(crate) struct Witness(pub(crate) TransferLogic);

impl LogicWitness for Witness {
    fn verifying_key(&self) -> Digest {
        verifying_key()
    }

    fn constrain(&self) -> anyhow::Result<LogicInstance> {
        LogicWitness::constrain(&self.0)
    }

    fn witness_to_vec(&self) -> anyhow::Result<Vec<u32>> {
        self.0.witness_to_vec()
    }

    fn proving_key(&self) -> Vec<u8> {
        ELF.to_vec()
    }
}
