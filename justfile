# Show commands before running (helps debug failures)
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe
default:
    @just --list

# --- Contracts ---

# Install contract dependencies
contracts-deps:
    cd contracts && forge soldeer install

# Clean contract dependencies
contracts-deps-clean:
    cd contracts && forge soldeer clean

# Clean contracts
contracts-clean:
    cd contracts && forge clean

# Build contracts
contracts-build *args:
    cd contracts && forge build {{ args }}

# Run contract tests
contracts-test *args:
    cd contracts && forge test {{ args }}

# Regenerate Rust bindings from contracts
contracts-gen-bindings:
    cd contracts && forge clean && forge bind \
        --select '^(ERC20Forwarder|ERC20ForwarderV2|ERC20ForwarderV3|IProtocolAdapterSpecific|ILogicRefSpecific|IEmergencyMigratable)$' \
        --bindings-path ../bindings/src/generated/ \
        --module \
        --overwrite

# Simulate deployment (dry-run)
contracts-simulate token-transfer-circuit-id chain protocol-adapter *args:
    @echo "IS_TEST_DEPLOYMENT: $IS_TEST_DEPLOYMENT"
    @echo "EMERGENCY_COMMITTEE: $EMERGENCY_COMMITTEE"
    cd contracts && forge script script/DeployERC20Forwarder.s.sol:DeployERC20Forwarder \
        --sig "run(bool,address,bytes32,address)" $IS_TEST_DEPLOYMENT {{protocol-adapter}} {{token-transfer-circuit-id}} $EMERGENCY_COMMITTEE \
        --rpc-url {{chain}} {{ args }}

# Deploy ERC20 forwarder
contracts-deploy deployer token-transfer-circuit-id chain protocol-adapter *args:
    cd contracts && forge script script/DeployERC20Forwarder.s.sol:DeployERC20Forwarder \
        --sig "run(bool,address,bytes32,address)" $IS_TEST_DEPLOYMENT {{protocol-adapter}} {{token-transfer-circuit-id}} $EMERGENCY_COMMITTEE \
         --broadcast --rpc-url {{chain}} {{ args }} --account {{deployer}} {{ args }}

# Verify on sourcify
contracts-verify-sourcify address chain *args:
    cd contracts && forge verify-contract {{address}} \
        src/ERC20Forwarder.sol:ERC20Forwarder \
        --chain {{chain}} --verifier sourcify {{ args }}

# Verify on etherscan
contracts-verify-etherscan address chain *args:
    cd contracts && forge verify-contract {{address}} \
        src/ERC20Forwarder.sol:ERC20Forwarder \
        --chain {{chain}} --verifier etherscan {{ args }}

# Verify on both sourcify and etherscan
contracts-verify address chain: (contracts-verify-sourcify address chain) (contracts-verify-etherscan address chain)

# Publish contracts
contracts-publish version *args:
    cd contracts && forge soldeer push anomapay-erc20-forwarder~{{version}} {{ args }}

# --- Bindings ---

# Clean bindings
bindings-clean:
    cd bindings && cargo clean

# Build bindings
bindings-build *args:
    cd bindings && cargo build {{ args }}

# Test bindings
bindings-test *args:
    cd bindings && cargo test {{ args }}

# Check bindings are up-to-date
bindings-check: contracts-gen-bindings
    git diff --exit-code bindings/src/generated/

# Publish bindings
bindings-publish *args:
    cd bindings && cargo publish {{ args }}

# --- All ---

# Build all (contracts + bindings)
all-build:
    @echo "==> Building contracts..."
    @just contracts-build
    @echo "==> Building bindings..."
    @just bindings-build

# Test all (contracts + bindings)
all-test:
    @echo "==> Testing contracts..."
    @just contracts-test
    @echo "==> Testing bindings..."
    @just bindings-test

# Prerequisites check
all-check:
    git status
    @echo "==> Checking bindings are up-to-date..."
    @just bindings-check
