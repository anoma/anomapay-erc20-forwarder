//! A build script to compile the forwarder contract and generate version information.

use std::process::Command;

use vergen::{BuildBuilder, Emitter, RustcBuilder};
use vergen_git2::Git2Builder;
extern crate vergen;

/// Fetch environment information during build.
/// Used to return git commit in the health endpoint in the webserver.
fn version_info() {
    // Rebuild the contracts if any file has changed in the contracts dir.

    let build = BuildBuilder::all_build().unwrap();
    let rustc = RustcBuilder::all_rustc().unwrap();
    let git2 = Git2Builder::all_git().unwrap();

    Emitter::default()
        .add_instructions(&build)
        .unwrap()
        .add_instructions(&rustc)
        .unwrap()
        .add_instructions(&git2)
        .unwrap()
        .emit()
        .unwrap()
}

/// Build all the solidity contracts.
fn build_contracts() {
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
}

fn main() {
    // Rebuild when the contracts or the source code changes.
    println!("cargo:rerun-if-changed=src/");
    println!("cargo:rerun-if-changed=../contracts/");

    // output the version information about this build
    version_info();

    // build the solidity contracts
    build_contracts();
}
