use alloy_primitives::{Address, B256, U256};
use alloy_sol_types::{SolValue, sol};

sol! {
    #[derive(Debug, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
    enum CallType {
        Wrap, // mint with permit info
        Unwrap // burn
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
    pub fn from_bytes(token: &[u8], amount: u128, nonce: &[u8], deadline: &[u8]) -> Self {
        let token_addr: Address = token.try_into().expect("Invalid address bytes");
        PermitTransferFrom {
            permitted: TokenPermissions {
                token: token_addr,
                amount: U256::from(amount),
            },
            nonce: B256::from_slice(nonce),
            deadline: B256::from_slice(deadline),
        }
    }
}

pub fn encode_transfer(token: &[u8], to: &[u8], value: u128) -> Vec<u8> {
    // This is only used in circuits, just let it panic if the address is invalid
    // Encode as (CallType, token, to, value)
    let token: Address = token.try_into().expect("Invalid address bytes");
    let to: Address = to.try_into().expect("Invalid address bytes");
    let value = U256::from(value);
    (CallType::Unwrap, token, to, value).abi_encode_params()
}

pub fn encode_permit_witness_transfer_from(
    from: &[u8],
    permit: PermitTransferFrom,
    witness: &[u8],
    signature: &[u8],
) -> Vec<u8> {
    // This is only used in circuits, just let it panic if the address is invalid
    let from: Address = from.try_into().expect("Invalid address bytes");
    (
        CallType::Wrap,
        from,
        permit,
        B256::from_slice(witness),
        signature,
    )
        .abi_encode_params()
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
fn encode_permit_witness_transfer_from_test() {
    let token = hex::decode("2222222222222222222222222222222222222222").unwrap();
    let from = hex::decode("3333333333333333333333333333333333333333").unwrap();
    let value = 1000u128;
    let permit = PermitTransferFrom::from_bytes(&token, value, &[1u8; 32], &[2u8; 32]);
    let witness = vec![3u8; 32];
    let signature = vec![4u8; 65];

    let encoded = encode_permit_witness_transfer_from(&from, permit, &witness, &signature);
    println!("encode: {:?}", hex::encode(&encoded));
    println!("len: {}", encoded.len());
}
