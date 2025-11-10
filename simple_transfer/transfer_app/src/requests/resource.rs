use crate::requests::DecodingErr::{
    ArrayDecodingError, DigestDecodingError, ResourceInvalidNullifierKeyCommitment,
};
use crate::requests::{to_array, DecodeResult, Expand};
use arm::nullifier_key::NullifierKeyCommitment;
use arm::resource::Resource;
use serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;

/// Defines teh shape of a resource sent via JSON to the API.
/// Implements functions
#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq, Clone)]
pub struct JsonResource {
    #[serde_as(as = "Base64")]
    pub logic_ref: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub label_ref: Vec<u8>,
    pub quantity: u128,
    #[serde_as(as = "Base64")]
    pub value_ref: Vec<u8>,
    pub is_ephemeral: bool,
    #[serde_as(as = "Base64")]
    pub nonce: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub nk_commitment: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub rand_seed: Vec<u8>,
}

impl Expand for Resource {
    type Struct = JsonResource;
    type Error = Box<dyn std::error::Error>;

    fn simplify(&self) -> JsonResource {
        JsonResource {
            logic_ref: self.logic_ref.clone().as_bytes().to_vec(),
            label_ref: self.label_ref.clone().as_bytes().to_vec(),
            quantity: self.quantity,
            value_ref: self.value_ref.clone().as_bytes().to_vec(),
            is_ephemeral: self.is_ephemeral,
            nonce: self.nonce.clone().to_vec(),
            nk_commitment: self.nk_commitment.as_bytes().to_vec(),
            rand_seed: self.rand_seed.clone().to_vec(),
        }
    }

    fn expand(json_resource: JsonResource) -> DecodeResult<Self> {
        let nk_commitment_bytes: [u8; 32] = to_array(json_resource.nk_commitment, "nk_commitment")
            .map_err(|_| ResourceInvalidNullifierKeyCommitment)?;

        let nk_commitment = NullifierKeyCommitment::from_bytes(&nk_commitment_bytes)
            .map_err(|_| ResourceInvalidNullifierKeyCommitment)?;

        Ok(Resource {
            logic_ref: json_resource
                .logic_ref
                .try_into()
                .map_err(|_| DigestDecodingError("logic_ref".to_string()))?,
            label_ref: json_resource
                .label_ref
                .try_into()
                .map_err(|_| DigestDecodingError("label_ref".to_string()))?,
            quantity: json_resource.quantity,
            value_ref: json_resource
                .value_ref
                .try_into()
                .map_err(|_| DigestDecodingError("value_ref".to_string()))?,
            is_ephemeral: json_resource.is_ephemeral,
            nonce: json_resource
                .nonce
                .try_into()
                .map_err(|_| ArrayDecodingError("nonce".to_string()))?,
            nk_commitment,
            rand_seed: json_resource
                .rand_seed
                .try_into()
                .map_err(|_| ArrayDecodingError("rand_seed".to_string()))?,
        })
    }
}
