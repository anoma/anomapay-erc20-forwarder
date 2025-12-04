use alloy_primitives::{Address, B256, U256};
use alloy_sol_types::{SolValue, sol};
use arm::error::ArmError;

sol! {
    #[derive(Debug, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
    enum CallTypeV2 {
        Wrap,
        Unwrap,
        Migrate,
    }
}

pub fn encode_migrate_forwarder_input(
    token: &[u8],
    quantity: u128,
    nf: &[u8],
    commitment_tree_root: &[u8],
    migrate_resource_logic_ref: &[u8],
    migrate_resource_forwarder_addr: &[u8],
) -> Result<Vec<u8>, ArmError> {
    let token: Address = token
        .try_into()
        .map_err(|_| ArmError::ProveFailed("Invalid address bytes".to_string()))?;

    // NOTE: u128 is padded to u256, this can be fixed if we extend the value to 248 bits in ARM
    let quantity_value = U256::from(quantity);

    let forwarder_addr_v1: Address = migrate_resource_forwarder_addr
        .try_into()
        .map_err(|_| ArmError::ProveFailed("Invalid address bytes".to_string()))?;

    Ok((
        CallTypeV2::Migrate,
        token,
        quantity_value,
        B256::from_slice(nf),
        B256::from_slice(commitment_tree_root),
        B256::from_slice(migrate_resource_logic_ref),
        forwarder_addr_v1,
    )
        .abi_encode_params())
}
