//! A build script to compile the forwarder contract.

use std::process::Command;

fn main() {
    // Make sure forge is available.
    if Command::new("forge").arg("--version").output().is_err() {
        println!("cargo:warning=forge not found, skipping contract compilation");
        return;
    }

    // Run forge build --ast in the `../contracts` directory.
    let status = Command::new("forge")
        .current_dir("../../contracts")
        .args(["build", "--ast"])
        .status()
        .expect("failed to run forge command");

    if !status.success() {
        panic!("forge build --ast command failed");
    }

    // Rebuild the contracts if any file has changed in the contracts dir.
    println!("cargo:rerun-if-changed=../contracts/");
}
