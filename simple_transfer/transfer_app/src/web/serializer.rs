use rocket::serde::Serialize;
use serde::Deserialize;
use serde_with::{base64::Base64, serde_as};
use utoipa::ToSchema;

#[serde_as]
#[derive(Debug, Serialize, Deserialize, ToSchema)]
/// This resource represents the way a Resource is serialized and deserialized.
/// It is only used internally by the serializer and deserializer, and to generate the OpenAPI schema.
pub struct SerializedResource {
    #[serde_as(as = "Base64")]
    #[schema(value_type = String, format = Binary)]
    pub logic_ref: [u8; 32],
    #[serde_as(as = "Base64")]
    #[schema(value_type = String, format = Binary)]
    pub label_ref: [u8; 32],
    pub quantity: u128,
    #[serde_as(as = "Base64")]
    #[schema(value_type = String, format = Binary)]
    pub value_ref: [u8; 32],
    pub is_ephemeral: bool,
    #[serde_as(as = "Base64")]
    #[schema(value_type = String, format = Binary)]
    pub nonce: [u8; 32],
    #[serde_as(as = "Base64")]
    #[schema(value_type = String, format = Binary)]
    pub nk_commitment: [u8; 32],
    #[serde_as(as = "Base64")]
    #[schema(value_type = String, format = Binary)]
    pub rand_seed: [u8; 32],
}

/// Serialization and deserialization for `NullifierKey` struct.
///
/// Serializes the nullifier key it's inner bytes as base64 encoded strings.
pub mod serialize_nullifier_key {
    use arm::nullifier_key::NullifierKey;
    use base64::engine::general_purpose;
    use base64::Engine;
    use general_purpose::STANDARD;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &NullifierKey, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        // Convert to something serializable
        // For example, if CustomType has a method to get a string representation:
        let inner_bytes = value.inner();
        serializer.serialize_str(STANDARD.encode(inner_bytes).as_str())
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<NullifierKey, D::Error>
    where
        D: Deserializer<'de>,
    {
        // Deserialize from the format you chose above
        let s = String::deserialize(deserializer)?;
        let bytes = STANDARD.decode(&s).map_err(serde::de::Error::custom)?;

        Ok(NullifierKey::from_bytes(bytes.as_ref()))
    }
}

/// Serialization and deserialization for `AffinePoint` struct.
///
/// Serializes by turning the affine point into a vector, and then base64
/// encoding it.
pub mod serialize_affine_point {
    use base64::engine::general_purpose;
    use base64::Engine;
    use k256::AffinePoint;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &AffinePoint, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let bytes = serde_json::to_vec(value).map_err(serde::ser::Error::custom)?;
        let base64_str = general_purpose::STANDARD.encode(&bytes);
        serializer.serialize_str(base64_str.as_str())
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<AffinePoint, D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        let bytes = general_purpose::STANDARD
            .decode(&s)
            .map_err(serde::de::Error::custom)?;
        serde_json::from_slice(&bytes).map_err(serde::de::Error::custom)
    }
}

/// Serializes the `AuthVerifyingKey` struct.
///
/// Serializes it by converting it to an affinepoint and then converting that to
/// base64.
pub mod serialize_auth_verifying_key {
    use arm::authorization::AuthorizationVerifyingKey;
    use base64::engine::general_purpose;
    use base64::Engine;
    use k256::AffinePoint;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &AuthorizationVerifyingKey, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let value = value.as_affine();
        let bytes = serde_json::to_vec(value).map_err(serde::ser::Error::custom)?;
        let base64_str = general_purpose::STANDARD.encode(&bytes);
        serializer.serialize_str(base64_str.as_str())
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<AuthorizationVerifyingKey, D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        let bytes = general_purpose::STANDARD
            .decode(&s)
            .map_err(serde::de::Error::custom)?;
        let affine_point: AffinePoint =
            serde_json::from_slice(&bytes).map_err(serde::de::Error::custom)?;
        Ok(AuthorizationVerifyingKey::from_affine(affine_point))
    }
}

pub mod serialize_authorization_signature {
    use arm::authorization::AuthorizationSignature;
    use base64::engine::general_purpose;
    use base64::Engine;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &AuthorizationSignature, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let bytes = serde_json::to_vec(value).map_err(serde::ser::Error::custom)?;
        let base64_str = general_purpose::STANDARD.encode(&bytes);
        serializer.serialize_str(base64_str.as_str())
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<AuthorizationSignature, D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        let bytes = general_purpose::STANDARD
            .decode(&s)
            .map_err(serde::de::Error::custom)?;
        let signature = AuthorizationSignature::from_bytes(bytes.as_slice()).map_err(|e| {
            serde::de::Error::custom(format!("Invalid base64 for signature: {}", e))
        })?;
        Ok(signature)
    }
}

/// Serializes a `Resource` struct.
///
/// The struct cannot be directly serialized, so it is first converted to
/// `SerializedResource`. This resource has each field converted to a simpler
/// value type like arrays.
///
/// Serializing is derived for that struct and is then punted there.
pub mod serialize_resource {
    use crate::web::serializer::SerializedResource;
    use arm::nullifier_key::NullifierKeyCommitment;
    use arm::resource::Resource;
    use arm::Digest;
    use serde::{Deserialize, Deserializer, Serialize, Serializer};

    /// Converts a Digest into a [u8;32] safely.
    fn into_arr<S>(digest: Digest) -> Result<[u8; 32], S::Error>
    where
        S: Serializer,
    {
        let slice = digest.as_bytes();
        let array: [u8; 32] = slice
            .try_into()
            .map_err(|_e| serde::ser::Error::custom("Digest not 32 bytes".to_string()))?;
        Ok(array)
    }

    pub fn serialize<S>(value: &Resource, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let logic_ref = into_arr::<S>(value.logic_ref)?;
        let label_ref = into_arr::<S>(value.label_ref)?;
        let quantity = value.quantity;
        let value_ref = into_arr::<S>(value.value_ref)?;
        let is_ephemeral = value.is_ephemeral;
        let nonce = value.nonce;
        let nk_commitment = into_arr::<S>(value.nk_commitment.inner())?;
        let rand_seed = value.rand_seed;
        SerializedResource {
            logic_ref,
            label_ref,
            quantity,
            value_ref,
            is_ephemeral,
            nonce,
            nk_commitment,
            rand_seed,
        }
        .serialize(serializer)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Resource, D::Error>
    where
        D: Deserializer<'de>,
    {
        let helper: SerializedResource = SerializedResource::deserialize(deserializer)?;
        let logic_ref = Digest::from_bytes(helper.logic_ref);
        let label_ref = Digest::from_bytes(helper.label_ref);
        let quantity = helper.quantity;
        let value_ref = Digest::from_bytes(helper.value_ref);
        let is_ephemeral = helper.is_ephemeral;
        let nonce = helper.nonce;
        let nk_commitment = NullifierKeyCommitment::from_bytes(&helper.nk_commitment)
            .map_err(|_| serde::de::Error::custom("nk_commitment not 32 bytes".to_string()))?;

        let rand_seed = helper.rand_seed;
        Ok(Resource {
            logic_ref,
            label_ref,
            quantity,
            value_ref,
            is_ephemeral,
            nonce,
            nk_commitment,
            rand_seed,
        })
    }
}
