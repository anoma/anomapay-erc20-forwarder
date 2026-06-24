use anoma_rm_risc0::Digest;
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;

#[derive(Clone, Debug, Default)]
pub struct Overrides {
    pub quantity: Option<u128>,
    pub consumed_label_ref: Option<Digest>,
    pub consumed_value_ref: Option<Digest>,
    pub auth_signature: Option<AuthoritySignature>,
}

impl Overrides {
    pub fn invalid_label_ref() -> Self {
        Self {
            consumed_label_ref: Some(Digest::default()),
            ..Self::default()
        }
    }

    pub fn invalid_value_ref() -> Self {
        Self {
            consumed_value_ref: Some(Digest::default()),
            ..Self::default()
        }
    }

    pub fn invalid_auth_signature() -> Self {
        let fake = anoma_rm_risc0_gadgets::authority::AuthoritySigningKey::from_bytes(&[9u8; 32])
            .expect("valid deterministic auth key bytes")
            .sign(transfer_witness::AUTH_SIGNATURE_DOMAIN, &[0u8; 32]);
        Self {
            auth_signature: Some(fake),
            ..Self::default()
        }
    }
}
