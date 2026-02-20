use alloy_chains::NamedChain;
use serde::{Deserialize, Serialize};
use std::{env, fs, process};

/// A single entry in deployments.json.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeploymentEntry {
    network: String,
    chain_id: u64,
    contract_address: String,
    version: String,
    protocol_adapter_address: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    tx_hash: Option<String>,
}

/// Minimal subset of Foundry's broadcast run-latest.json.
#[derive(Deserialize)]
struct BroadcastArtifact {
    transactions: Vec<BroadcastTransaction>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BroadcastTransaction {
    transaction_type: String,
    contract_name: Option<String>,
    contract_address: Option<String>,
    hash: Option<String>,
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 4 {
        eprintln!(
            "Usage: {} <chain> <version> <protocol-adapter-address>",
            args[0]
        );
        eprintln!(
            "Example: {} mainnet 1.0.1 0x0eA3B55b68A3f307c8FE3fe66E443247c95F0CfF",
            args[0]
        );
        process::exit(1);
    }

    let chain_name = &args[1];
    let version = &args[2];
    let protocol_adapter_address = &args[3];

    // Resolve chain ID from name.
    let chain: NamedChain = chain_name.parse().unwrap_or_else(|_| {
        eprintln!("Unknown chain: {chain_name}");
        process::exit(1);
    });
    let chain_id: u64 = chain.into();

    // Read broadcast artifact.
    let script_name = "DeployERC20Forwarder.s.sol";
    let contract_name = "ERC20Forwarder";
    let artifact_path = format!("contracts/broadcast/{script_name}/{chain_id}/run-latest.json");

    let artifact_json = fs::read_to_string(&artifact_path).unwrap_or_else(|_| {
        eprintln!("Broadcast artifact not found: {artifact_path}");
        eprintln!("Run `just contracts-deploy` first.");
        process::exit(1);
    });

    let artifact: BroadcastArtifact = serde_json::from_str(&artifact_json).unwrap_or_else(|e| {
        eprintln!("Failed to parse broadcast artifact: {e}");
        process::exit(1);
    });

    // Find the CREATE/CREATE2 transaction for our contract.
    let tx = artifact
        .transactions
        .iter()
        .find(|t| {
            matches!(t.transaction_type.as_str(), "CREATE" | "CREATE2")
                && t.contract_name.as_deref() == Some(contract_name)
        })
        .unwrap_or_else(|| {
            eprintln!("No {contract_name} deployment found in {artifact_path}");
            process::exit(1);
        });

    let contract_address = tx.contract_address.as_ref().unwrap();
    let tx_hash = tx.hash.clone();

    // Read existing deployments.json.
    let deployments_path = "deployments.json";
    let mut entries: Vec<DeploymentEntry> = {
        let json = fs::read_to_string(deployments_path).unwrap_or_else(|_| "[]".to_string());
        serde_json::from_str(&json).unwrap_or_else(|e| {
            eprintln!("Failed to parse {deployments_path}: {e}");
            process::exit(1);
        })
    };

    // Remove existing entry for this chain (if any) and add new one.
    entries.retain(|e| e.chain_id != chain_id);
    entries.push(DeploymentEntry {
        network: chain_name.to_string(),
        chain_id,
        contract_address: contract_address.to_string(),
        version: version.to_string(),
        protocol_adapter_address: protocol_adapter_address.to_string(),
        tx_hash: tx_hash.clone(),
    });

    // Sort by chain ID for deterministic output.
    entries.sort_by_key(|e| e.chain_id);

    // Write back.
    let json = serde_json::to_string_pretty(&entries).expect("Failed to serialize deployments");
    fs::write(deployments_path, json + "\n").expect("Failed to write deployments.json");

    println!("Recorded {contract_name} deployment on {chain_name} (chain {chain_id}):");
    println!("  address:          {contract_address}");
    println!("  protocolAdapter:  {protocol_adapter_address}");
    if let Some(hash) = &tx_hash {
        println!("  tx:               {hash}");
    }
}
