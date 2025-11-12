use crate::errors::TransactionError;
use crate::errors::TransactionError::VerificationFailure;
use alloy::primitives::Address;
use arm::transaction::Transaction;

/// Parse a Vec<u8> into an Address struct.
pub fn parse_address(address_bytes: Vec<u8>) -> Option<Address> {
    let bytes: Result<[u8; 20], _> = address_bytes.try_into();
    match bytes {
        Ok(bytes) => Some(Address::from_slice(&bytes)),

        _ => None,
    }
}

/// Verifies a transaction. Returns an error if verification failed.
pub fn verify_transaction(transaction: Transaction) -> Result<(), TransactionError> {
    transaction.verify().map_err(|_| VerificationFailure)
}
