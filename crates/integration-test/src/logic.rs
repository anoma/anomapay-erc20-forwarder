//! The shared anomapay-erc20 token-transfer resource logic: its verifying key
//! and the [`LogicWitness`] adapter over [`TokenTransferWitness`] that every
//! action kind (wrap / transfer / unwrap) feeds to the prover.

use anoma_pa_testkit::witness::LogicWitness;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::logic_instance::LogicInstance;
use anoma_rm_risc0::logic_proof::LogicProver;
use anoma_rm_risc0::resource_logic::LogicCircuit;
use anyhow::Context;
use transfer_library::TransferLogic;
use transfer_witness::TokenTransferWitness;

/// Verifying key (image id) of the anomapay-erc20 token-transfer resource logic.
#[inline]
pub fn verifying_key() -> Digest {
    *transfer_library::TOKEN_TRANSFER_ID
}

/// Adapts a [`TokenTransferWitness`] to the testkit's [`LogicWitness`] trait.
pub(crate) struct Witness {
    inner: TokenTransferWitness,
}

impl Witness {
    #[inline]
    pub(crate) fn new(inner: TokenTransferWitness) -> Self {
        Self { inner }
    }
}

impl LogicWitness for Witness {
    fn verifying_key(&self) -> Digest {
        verifying_key()
    }

    fn constrain(&self) -> anyhow::Result<LogicInstance> {
        LogicCircuit::constrain(&self.inner)
            .map_err(anyhow::Error::from)
            .context("invalid transfer logic witness")
    }

    fn witness_to_vec(&self) -> anyhow::Result<Vec<u32>> {
        risc0_zkvm::serde::to_vec(&self.inner)
            .context("failed to serialize transfer logic witness to risc0 words")
    }

    fn proving_key(&self) -> Vec<u8> {
        TransferLogic::proving_key().to_vec()
    }
}
