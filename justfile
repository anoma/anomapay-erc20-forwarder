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

# Lint contracts (forge lint + solhint)
contracts-lint:
    cd contracts && forge lint --deny warnings
    cd contracts && bunx --bun solhint --config .solhint.json 'src/**/*.sol'
    cd contracts && bunx --bun solhint --config .solhint.other.json 'test/**/*.sol'
    cd contracts && bunx --bun solhint --config .solhint.other.json 'script/**/*.sol'

# Format contracts
contracts-fmt *args:
    cd contracts && forge fmt {{ args }}

# Check contract formatting
contracts-fmt-check:
    cd contracts && forge fmt --check

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
         --broadcast --rpc-url {{chain}} --account {{deployer}} {{ args }}

# Simulate deployment v2 (dry-run)
contracts-simulate-v2 logic-ref-v2 chain protocol-adapter-v2 erc20-forwarder-v1 *args:
    @echo "EMERGENCY_COMMITTEE: $EMERGENCY_COMMITTEE"
    cd contracts && forge script script/DeployERC20ForwarderV2.s.sol:DeployERC20ForwarderV2 \
        --sig "run(address,bytes32,address,address)" {{protocol-adapter-v2}} {{logic-ref-v2}} $EMERGENCY_COMMITTEE {{erc20-forwarder-v1}} \
        --rpc-url {{chain}} {{ args }}

# Deploy ERC20 forwarder v2
contracts-deploy-v2 deployer logic-ref-v2 chain protocol-adapter-v2 erc20-forwarder-v1 *args:
    cd contracts && forge script script/DeployERC20ForwarderV2.s.sol:DeployERC20ForwarderV2 \
        --sig "run(address,bytes32,address,address)" {{protocol-adapter-v2}} {{logic-ref-v2}} $EMERGENCY_COMMITTEE {{erc20-forwarder-v1}} \
        --broadcast --rpc-url {{chain}} --account {{deployer}} {{ args }}

# Verify on sourcify
contracts-verify-sourcify address chain *args:
    cd contracts && env -u ETHERSCAN_API_KEY forge verify-contract {{address}} \
        src/ERC20Forwarder.sol:ERC20Forwarder \
        --chain {{chain}} --verifier sourcify --watch {{ args }}

# Verify on etherscan
contracts-verify-etherscan address chain *args:
    cd contracts && forge verify-contract {{address}} \
        src/ERC20Forwarder.sol:ERC20Forwarder \
        --chain {{chain}} --verifier etherscan --watch {{ args }}

# Verify on both sourcify and etherscan
contracts-verify address chain: (contracts-verify-sourcify address chain) (contracts-verify-etherscan address chain)

# Publish contracts
contracts-publish version *args:
    cd contracts && forge soldeer push anomapay-erc20-forwarder~{{version}} {{ args }}

# --- Bindings ---

# Lint bindings (clippy)
bindings-lint:
    cd bindings && cargo clippy --no-deps -- -Dwarnings
    cd bindings && cargo clippy --no-deps --tests -- -Dwarnings

# Format bindings
bindings-fmt *args:
    cd bindings && cargo fmt {{ args }}

# Check bindings formatting
bindings-fmt-check:
    cd bindings && cargo fmt -- --check

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

# Lint all (contracts + bindings)
all-lint:
    @echo "==> Linting contracts..."
    @just contracts-lint
    @echo "==> Linting bindings..."
    @just bindings-lint

# Format all (contracts + bindings)
all-fmt:
    @echo "==> Formatting contracts..."
    @just contracts-fmt
    @echo "==> Formatting bindings..."
    @just bindings-fmt

# Check formatting (contracts + bindings)
all-fmt-check:
    @echo "==> Checking contracts formatting..."
    @just contracts-fmt-check
    @echo "==> Checking bindings formatting..."
    @just bindings-fmt-check

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
