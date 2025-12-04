use alloy_primitives::{Address, B256, U256};
use alloy_sol_types::{SolValue, sol};
use arm::error::ArmError;

sol! {
    #[derive(Debug, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
    enum CallType {
        Wrap,
        Unwrap
    }

    /// @notice The token and amount details for a transfer signed in the permit transfer signature
    struct TokenPermissions {
        // ERC20 token address
        address token;
        // the maximum amount that can be spent
        uint256 amount;
    }

    /// @notice The signed permit message for a single token transfer
    struct PermitTransferFrom {
        TokenPermissions permitted;
        // a unique value for every token owner's signature to prevent signature replays
        // In permit2, this is a uint256
        bytes32 nonce;
        // deadline on the permit signature
        // In permit2, this is a uint256
        bytes32 deadline;
    }
}

impl PermitTransferFrom {
    pub fn from_bytes(
        token: &[u8],
        amount: u128,
        nonce: &[u8],
        deadline: &[u8],
    ) -> Result<Self, ArmError> {
        let token_addr: Address = token
            .try_into()
            .map_err(|_| ArmError::ProveFailed("Invalid token address bytes".to_string()))?;
        Ok(PermitTransferFrom {
            permitted: TokenPermissions {
                token: token_addr,
                amount: U256::from(amount),
            },
            nonce: B256::from_slice(nonce),
            deadline: B256::from_slice(deadline),
        })
    }
}

pub fn encode_unwrap_forwarder_input(
    token: &[u8],
    ethereum_account_addr: &[u8],
    value: u128,
) -> Result<Vec<u8>, ArmError> {
    // Encode as (CallType, token, to, value)
    let token: Address = token
        .try_into()
        .map_err(|_| ArmError::ProveFailed("Invalid token address bytes".to_string()))
        .unwrap();
    let to: Address = ethereum_account_addr
        .try_into()
        .map_err(|_| ArmError::ProveFailed("Invalid to address bytes".to_string()))
        .unwrap();
    let value = U256::from(value);
    Ok((CallType::Unwrap, token, to, value).abi_encode_params())
}

pub fn encode_wrap_forwarder_input(
    ethereum_account_addr: &[u8],
    permit: PermitTransferFrom,
    witness: &[u8],
    signature: &[u8],
) -> Result<Vec<u8>, ArmError> {
    let from: Address = ethereum_account_addr
        .try_into()
        .map_err(|_| ArmError::ProveFailed("Invalid from address bytes".to_string()))?;
    Ok((
        CallType::Wrap,
        from,
        permit,
        B256::from_slice(witness),
        signature,
    )
        .abi_encode_params())
}

#[test]
fn forward_call_data_test() {
    use arm_gadgets::evm::ForwarderCalldata;
    // Example data
    let addr = hex::decode("ffffffffffffffffffffffffffffffffffffffff").unwrap();
    let input = hex::decode("ab").unwrap();
    let output = hex::decode("cd").unwrap();

    // Create instance
    let data = ForwarderCalldata::from_bytes(&addr, input, output);

    // abi encode
    let encoded_data = data.encode();
    println!("encode: {:?}", hex::encode(&encoded_data));
    println!("len: {}", encoded_data.len());
    let decoded_data = ForwarderCalldata::decode(&encoded_data).unwrap();

    assert_eq!(data.untrustedForwarder, decoded_data.untrustedForwarder);
    assert_eq!(data.input, decoded_data.input);
    assert_eq!(data.output, decoded_data.output);
}

#[test]
fn encode_wrap_forwarder_input_test() {
    let token = hex::decode("2222222222222222222222222222222222222222").unwrap();
    let from = hex::decode("3333333333333333333333333333333333333333").unwrap();
    let value = 1000u128;
    let permit = PermitTransferFrom::from_bytes(&token, value, &[1u8; 32], &[2u8; 32]).unwrap();
    let witness = vec![3u8; 32];
    let signature = vec![4u8; 65];

    let encoded = encode_wrap_forwarder_input(&from, permit, &witness, &signature).unwrap();
    println!("encode: {:?}", hex::encode(&encoded));
    println!("len: {}", encoded.len());
}
