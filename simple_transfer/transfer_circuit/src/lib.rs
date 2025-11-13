// Add circuit tests here

// use simple_transfer_methods::{SIMPLE_TRANSFER_GUEST_ELF, SIMPLE_TRANSFER_GUEST_ID};

#[test]
fn print_transfer_logic_id() {
    use risc0_zkvm::sha::Digest;
    use simple_transfer_methods::SIMPLE_TRANSFER_GUEST_ID;

    // Print the ID
    println!(
        "SIMPLE_TRANSFER_GUEST_ID: {:?}",
        Digest::from(SIMPLE_TRANSFER_GUEST_ID)
    );
}
