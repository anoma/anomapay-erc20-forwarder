//! The transfer witness library holds the struct to generate proofs over resource logics for
//! simple transfer resources in the Anoma Pay application.
//!
pub mod call_type_v2;
use crate::call_type_v2::{encode_migrate_forwarder_input, CallTypeV2};
pub use arm::resource_logic::LogicCircuit;
use arm::{
    error::ArmError,
    logic_instance::{AppData, ExpirableBlob, LogicInstance},
    merkle_path::MerklePath,
    nullifier_key::NullifierKey,
    resource::Resource,
    utils::bytes_to_words,
    Digest,
};
use arm_gadgets::{encryption::Ciphertext, evm::ForwarderCalldata};
use serde::{Deserialize, Serialize};
use transfer_witness::{
    calculate_label_ref, calculate_value_ref_from_auth, calculate_value_ref_from_user_addr,
    call_type::{encode_unwrap_forwarder_input, encode_wrap_forwarder_input, PermitTransferFrom},
    AuthorizationInfo, DeletionCriterion, EncryptionInfo, LabelInfo, PermitInfo, ResourceWithLabel,
};

pub const AUTH_SIGNATURE_DOMAIN_V2: &[u8] = b"TokenTransferAuthorizationV2";

/// The TokenTransferWitnessV2 holds all the information necessary to generate a proof of the
/// resource logic of a given resource.
#[derive(Clone, Default, Serialize, Deserialize)]
pub struct TokenTransferWitnessV2 {
    /// Resource this witness is about.
    pub resource: Resource,
    /// Is this a consumed or created resource.
    pub is_consumed: bool,
    /// Action tree root
    pub action_tree_root: Digest,
    /// Nullifier key for the resource.
    pub nf_key: Option<NullifierKey>,
    /// See AuthorizationInfo struct.
    pub auth_info: Option<AuthorizationInfo>,
    /// See EncryptionInfo struct.
    pub encryption_info: Option<EncryptionInfo>,
    /// See ForwarderInfoV2 struct.
    pub forwarder_info_v2: Option<ForwarderInfoV2>,
    /// See LabelInfo struct.
    pub label_info: Option<LabelInfo>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct ForwarderInfoV2 {
    pub call_type: CallTypeV2,
    pub user_addr: Vec<u8>,
    pub permit_info: Option<PermitInfo>,
    // The migrate info is added for v2 witness to support migration from v1 to v2
    pub migrate_info: Option<MigrateInfo>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct MigrateInfo {
    pub resource: Resource,
    pub nf_key: NullifierKey,
    // Merkle path from cm-tree v1 to prove existence of the migrate_resource
    pub path: MerklePath,
    pub auth_info: AuthorizationInfo,
}

impl TokenTransferWitnessV2 {
    // Compute the tag
    pub fn tag(&self) -> Result<Digest, ArmError> {
        if self.is_consumed {
            let nf_key = self
                .nf_key
                .as_ref()
                .ok_or(ArmError::MissingField("Nullifier key"))?;
            self.resource.nullifier(nf_key)
        } else {
            Ok(self.resource.commitment())
        }
    }

    // check on ephemeral resources and return external_payload
    pub fn ephemeral_resource_check(
        &self,
        action_root: &[u8],
    ) -> Result<Vec<ExpirableBlob>, ArmError> {
        let forwarder_info = self
            .forwarder_info_v2
            .as_ref()
            .ok_or(ArmError::MissingField("Forwarder info"))?;

        let label_info = self
            .label_info
            .as_ref()
            .ok_or(ArmError::MissingField("Label info"))?;

        // Check resource label: label = sha2(forwarder_addr, erc20_addr)
        let forwarder_addr = label_info.forwarder_addr.as_ref();
        let erc20_addr = label_info.token_addr.as_ref();
        let user_addr = forwarder_info.user_addr.as_ref();
        let label_ref = calculate_label_ref(forwarder_addr, erc20_addr);
        if self.resource.label_ref != label_ref {
            return Err(ArmError::ProveFailed(
                "Invalid resource label_ref".to_string(),
            ));
        }

        // Check resource value_ref: value_ref[0..20] = user_addr
        // We need this check to ensure the permit2 signature covers
        // the correct user address. It signs over the action tree root,
        // and the tag containing the value_ref is directed to the tree root.
        let value_ref = calculate_value_ref_from_user_addr(user_addr);
        if self.resource.value_ref != value_ref {
            return Err(ArmError::ProveFailed(
                "Invalid resource value_ref".to_string(),
            ));
        }

        let inputs = match forwarder_info.call_type {
            CallTypeV2::Unwrap => {
                assert!(!self.is_consumed);
                encode_unwrap_forwarder_input(erc20_addr, user_addr, self.resource.quantity)
            }
            CallTypeV2::Wrap => {
                assert!(self.is_consumed);
                let permit_info = forwarder_info
                    .permit_info
                    .as_ref()
                    .ok_or(ArmError::MissingField("Permit info"))?;
                let permit = PermitTransferFrom::from_bytes(
                    erc20_addr,
                    self.resource.quantity,
                    permit_info.permit_nonce.as_ref(),
                    permit_info.permit_deadline.as_ref(),
                );
                encode_wrap_forwarder_input(
                    user_addr,
                    permit,
                    action_root,
                    permit_info.permit_sig.as_ref(),
                )
            }
            CallTypeV2::Migrate => {
                assert!(self.is_consumed);

                let migrate_info = forwarder_info
                    .migrate_info
                    .as_ref()
                    .ok_or(ArmError::MissingField("Migrate info"))?;

                // compute migrate resource commitment tree root
                let migrate_cm = migrate_info.resource.commitment();
                let migrate_root = migrate_info.path.root(&migrate_cm);

                // check migrate_resource is non-ephemeral
                assert!(!migrate_info.resource.is_ephemeral);

                // check migrate_resource authorization
                let auth_pk = &migrate_info.auth_info.auth_pk;
                if migrate_info.resource.value_ref != calculate_value_ref_from_auth(auth_pk) {
                    return Err(ArmError::ProveFailed(
                        "Invalid migrate resource value_ref".to_string(),
                    ));
                }

                if auth_pk
                    .verify(
                        AUTH_SIGNATURE_DOMAIN_V2,
                        action_root,
                        &migrate_info.auth_info.auth_sig,
                    )
                    .is_err()
                {
                    return Err(ArmError::InvalidSignature);
                }

                // check migrate_resource quantity
                if migrate_info.resource.quantity != self.resource.quantity {
                    return Err(ArmError::ProveFailed(
                        "Wrong migrate resource quantity".to_string(),
                    ));
                }

                // compute migrate resource nullifier
                let migrate_nf = migrate_info
                    .resource
                    .nullifier_from_commitment(&migrate_info.nf_key, &migrate_cm)?;

                encode_migrate_forwarder_input(
                    erc20_addr,
                    self.resource.quantity,
                    migrate_nf.as_bytes(),
                    migrate_root.as_bytes(),
                    migrate_info.resource.logic_ref.as_bytes(),
                    migrate_info.resource.label_ref.as_bytes(),
                )
            }
            _ => {
                return Err(ArmError::MissingField(
                    "Invalid call type for ephemeral resource",
                ));
            }
        };

        let forwarder_call_data = ForwarderCalldata::from_bytes(forwarder_addr, inputs, vec![]);
        let call_data_expirable_blob = ExpirableBlob {
            blob: bytes_to_words(&forwarder_call_data.encode()),
            deletion_criterion: DeletionCriterion::Immediately as u32,
        };
        Ok(vec![call_data_expirable_blob])
    }

    // check persistent resource consumption
    pub fn persistent_resource_consumption(&self, action_root: &[u8]) -> Result<(), ArmError> {
        let auth_info = self
            .auth_info
            .as_ref()
            .ok_or(ArmError::MissingField("Auth info"))?;

        // check value_ref
        if self.resource.value_ref != calculate_value_ref_from_auth(&auth_info.auth_pk) {
            return Err(ArmError::InvalidResourceValueRef);
        }

        // Verify the authorization signature
        if auth_info
            .auth_pk
            .verify(AUTH_SIGNATURE_DOMAIN_V2, action_root, &auth_info.auth_sig)
            .is_err()
        {
            return Err(ArmError::InvalidSignature);
        }

        Ok(())
    }

    /// check persistent resource creation and return discovery_payload and resource_payload
    pub fn persistent_resource_creation(
        &self,
    ) -> Result<(Vec<ExpirableBlob>, Vec<ExpirableBlob>), ArmError> {
        let label_info = self
            .label_info
            .as_ref()
            .ok_or(ArmError::MissingField("Label info"))?;
        let label_ref = calculate_label_ref(
            label_info.forwarder_addr.as_ref(),
            label_info.token_addr.as_ref(),
        );

        if self.resource.label_ref != label_ref {
            return Err(ArmError::ProveFailed(
                "Invalid resource label_ref".to_string(),
            ));
        }

        // Generate resource ciphertext
        let encryption_info = self
            .encryption_info
            .as_ref()
            .ok_or(ArmError::MissingField("Encryption info"))?;
        let payload_plaintext = bincode::serialize(&ResourceWithLabel {
            resource: self.resource,
            forwarder: label_info.token_addr.clone(),
            token: label_info.token_addr.clone(),
        })
        .map_err(|_| ArmError::InvalidResourceSerialization);
        let ciphertext = Ciphertext::encrypt_with_nonce(
            &payload_plaintext?,
            &encryption_info.receiver_pk,
            &encryption_info.sender_sk,
            encryption_info
                .encryption_nonce
                .clone()
                .try_into()
                .map_err(|_| ArmError::InvalidEncryptionNonce)?,
        )?;

        // Generate resource_payload
        let ciphertext_expirable_blob = ExpirableBlob {
            blob: ciphertext.as_words(),
            deletion_criterion: DeletionCriterion::Never as u32,
        };

        // Generate discovery_payload
        let ciphertext_discovery_blob = ExpirableBlob {
            blob: encryption_info.discovery_ciphertext.clone(),
            deletion_criterion: DeletionCriterion::Never as u32,
        };

        Ok((
            vec![ciphertext_discovery_blob],
            vec![ciphertext_expirable_blob],
        ))
    }
}

impl LogicCircuit for TokenTransferWitnessV2 {
    fn constrain(&self) -> Result<LogicInstance, ArmError> {
        // Load resources
        let cm = self.resource.commitment();
        let tag = if self.is_consumed {
            let nf_key = self
                .nf_key
                .as_ref()
                .ok_or(ArmError::MissingField("Nullifier key"))?;
            self.resource.nullifier_from_commitment(nf_key, &cm)?
        } else {
            cm
        };

        let root_bytes = self.action_tree_root.as_bytes();

        // Generate resource_payload and external_payload
        let (discovery_payload, resource_payload, external_payload) = if self.resource.is_ephemeral
        {
            let forwarder_info_v2 = self
                .forwarder_info_v2
                .as_ref()
                .ok_or(ArmError::MissingField("Forwarder info"))?;

            let label_info = self
                .label_info
                .as_ref()
                .ok_or(ArmError::MissingField("Label info"))?;

            // Check resource label: label = sha2(forwarder_addr, erc20_addr)
            let forwarder_addr = label_info.forwarder_addr.as_ref();
            let erc20_addr = label_info.token_addr.as_ref();
            let user_addr = forwarder_info_v2.user_addr.as_ref();
            let label_ref = calculate_label_ref(forwarder_addr, erc20_addr);
            assert_eq!(self.resource.label_ref, label_ref);

            // Check resource value_ref: value_ref[0..20] = user_addr
            let value_ref = calculate_value_ref_from_user_addr(user_addr);
            assert_eq!(self.resource.value_ref, value_ref);

            let input = match forwarder_info_v2.call_type {
                CallTypeV2::Unwrap => {
                    assert!(!self.is_consumed);
                    encode_unwrap_forwarder_input(erc20_addr, user_addr, self.resource.quantity)
                }
                CallTypeV2::Wrap => {
                    assert!(self.is_consumed);
                    let permit_info = forwarder_info_v2
                        .permit_info
                        .as_ref()
                        .ok_or(ArmError::MissingField("Permit info"))?;
                    let permit = PermitTransferFrom::from_bytes(
                        erc20_addr,
                        self.resource.quantity,
                        permit_info.permit_nonce.as_ref(),
                        permit_info.permit_deadline.as_ref(),
                    );
                    encode_wrap_forwarder_input(
                        user_addr,
                        permit,
                        root_bytes,
                        permit_info.permit_sig.as_ref(),
                    )
                }
                CallTypeV2::Migrate => {
                    assert!(self.is_consumed);

                    let migrate_info = forwarder_info_v2
                        .migrate_info
                        .as_ref()
                        .ok_or(ArmError::MissingField("Migrate info"))?;

                    // compute migrate resource commitment tree root
                    let migrate_cm = migrate_info.resource.commitment();
                    let migrate_root = migrate_info.path.root(&migrate_cm);

                    // check migrate_resource is non-ephemeral
                    assert!(!migrate_info.resource.is_ephemeral);

                    // check migrate_resource authorization
                    let auth_pk = &migrate_info.auth_info.auth_pk;
                    assert_eq!(
                        migrate_info.resource.value_ref,
                        calculate_value_ref_from_auth(auth_pk)
                    );
                    assert!(auth_pk
                        .verify(
                            AUTH_SIGNATURE_DOMAIN_V2,
                            root_bytes,
                            &migrate_info.auth_info.auth_sig
                        )
                        .is_ok());

                    // check migrate_resource quantity
                    assert_eq!(migrate_info.resource.quantity, self.resource.quantity);

                    // compute migrate resource nullifier
                    let migrate_nf = migrate_info
                        .resource
                        .nullifier_from_commitment(&migrate_info.nf_key, &migrate_cm)?;

                    encode_migrate_forwarder_input(
                        erc20_addr,
                        self.resource.quantity,
                        migrate_nf.as_bytes(),
                        migrate_root.as_bytes(),
                        migrate_info.resource.logic_ref.as_bytes(),
                        migrate_info.resource.label_ref.as_bytes(),
                    )
                }
                _ => {
                    return Err(ArmError::MissingField(
                        "Invalid call type for ephemeral resource",
                    ));
                }
            };

            let forwarder_call_data = ForwarderCalldata::from_bytes(forwarder_addr, input, vec![]);
            let external_payload = {
                let call_data_expirable_blob = ExpirableBlob {
                    blob: bytes_to_words(&forwarder_call_data.encode()),
                    deletion_criterion: DeletionCriterion::Never as u32,
                };
                vec![call_data_expirable_blob]
            };

            // Empty discovery_payload and resource_payload
            (vec![], vec![], external_payload)
        } else if self.is_consumed {
            // Consume a persistent resource
            self.persistent_resource_consumption(root_bytes)?;

            // empty payloads for consumed persistent resource
            (vec![], vec![], vec![])
        } else {
            // Create a persistent resource
            let (discovery_payload, resource_payload) = self.persistent_resource_creation()?;

            // return discovery_payload and resource_payload
            (discovery_payload, resource_payload, vec![])
        };

        let app_data = AppData {
            resource_payload,
            discovery_payload,
            external_payload,
            application_payload: vec![], // Empty application payload
        };

        Ok(LogicInstance {
            tag,
            is_consumed: self.is_consumed,
            root: self.action_tree_root,
            app_data,
        })
    }
}

impl TokenTransferWitnessV2 {
    /// Create a new transfer witness.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        resource: Resource,
        is_consumed: bool,
        action_tree_root: Digest,
        nf_key: Option<NullifierKey>,
        auth_info: Option<AuthorizationInfo>,
        encryption_info: Option<EncryptionInfo>,
        forwarder_info_v2: Option<ForwarderInfoV2>,
        label_info: Option<LabelInfo>,
    ) -> Self {
        Self {
            is_consumed,
            resource,
            action_tree_root,
            nf_key,
            auth_info,
            encryption_info,
            forwarder_info_v2,
            label_info,
        }
    }
}
