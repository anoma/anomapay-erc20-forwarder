// Add circuit tests here

#[test]
fn print_transfer_logic_id() {
    use risc0_zkvm::sha::Digest;
    use token_transfer_methods::TOKEN_TRANSFER_GUEST_ID;

    // Print the ID
    println!(
        "TOKEN_TRANSFER_GUEST_ID: {:?}",
        Digest::from(TOKEN_TRANSFER_GUEST_ID)
    );
}
