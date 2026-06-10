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

# Checks that the storage layout of contracts in `src` is empty.
# `skip` is a space-separated list of contract names to ignore (non-upgradeable bases).
contracts-storage-check *skip:
    #!/usr/bin/env bash
    set -euo pipefail
    cd contracts
    for sol in src/*.sol; do
        name="$(basename "$sol" .sol)"
        case " {{ skip }} " in *" $name "*) continue ;; esac
        if [ "$(forge inspect "$name" storageLayout --json | jq '.storage == []')" != true ]; then
            printf '{{RED}}%s has a non-empty storage layout; upgrade-safe contracts must use ERC-7201 namespaced storage.{{NORMAL}}\n' "$sol"
            exit 1
        fi
    done
    printf '{{GREEN}}All contracts in `src` use namespaced storage (empty storage layout).{{NORMAL}}\n'

# Run slither on contracts
contracts-static-analysis:
    cd contracts && slither .
    @echo "Removing slither compilation artifacts..."
    forge clean

# Format contracts
contracts-fmt *args:
    cd contracts && forge fmt {{ args }}

# Check contract formatting
contracts-fmt-check:
    cd contracts && forge fmt --check

# Run contract tests
contracts-test *args:
    cd contracts && forge test --force {{ args }}

# Regenerate Rust bindings from contracts
contracts-gen-bindings:
    cd contracts && forge clean && forge bind \
        --skip test --skip script \
        --select '^(ERC20Forwarder|ERC20ForwarderV2)$' \
        --bindings-path ../bindings/src/generated/ \
        --module \
        --overwrite

# Simulate deployment (dry-run)
contracts-simulate token-transfer-circuit-id chain protocol-adapter *args:
    @echo "IS_TEST_DEPLOYMENT: $IS_TEST_DEPLOYMENT"
    @echo "OWNER: $OWNER"
    @echo "Cleaning contracts to ensure reproducible build..."
    @just contracts-clean
    cd contracts && forge script script/DeployERC20ForwarderProxy.s.sol:DeployERC20Forwarder \
        --sig "run(bool,address,bytes32,address)" $IS_TEST_DEPLOYMENT {{protocol-adapter}} {{token-transfer-circuit-id}} $OWNER \
        --rpc-url {{chain}} {{ args }}

# Deploy ERC20 forwarder
contracts-deploy deployer token-transfer-circuit-id chain protocol-adapter *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just contracts-clean
    cd contracts && forge script script/DeployERC20ForwarderProxy.s.sol:DeployERC20Forwarder \
        --sig "run(bool,address,bytes32,address)" $IS_TEST_DEPLOYMENT {{protocol-adapter}} {{token-transfer-circuit-id}} $OWNER \
         --broadcast --rpc-url {{chain}} --account {{deployer}} {{ args }}

# Simulate upgrade (dry-run)
contracts-simulate-upgrade proxy logic-ref-v2 chain *args:
    @echo "IS_TEST_DEPLOYMENT: $IS_TEST_DEPLOYMENT"
    @echo "OWNER: $OWNER"
    @echo "Cleaning contracts to ensure reproducible build..."
    @just contracts-clean
    cd contracts && forge script script/UpgradeERC20ForwarderProxy.s.sol:UpgradeERC20Forwarder \
        --sig "run(bool,address,bytes32)" $IS_TEST_DEPLOYMENT {{proxy}} {{logic-ref-v2}} \
        --rpc-url {{chain}} --sender $OWNER {{ args }}

# Upgrade ERC20 forwarder to the V2 implementation
contracts-upgrade deployer proxy logic-ref-v2 chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just contracts-clean
    cd contracts && forge script script/UpgradeERC20ForwarderProxy.s.sol:UpgradeERC20Forwarder \
        --sig "run(bool,address,bytes32)" $IS_TEST_DEPLOYMENT {{proxy}} {{logic-ref-v2}} \
         --broadcast --rpc-url {{chain}} --account {{deployer}} {{ args }}

# Verify the implementation on sourcify
contracts-verify-impl-sourcify address chain *args:
    cd contracts && env -u ETHERSCAN_API_KEY forge verify-contract {{address}} \
        src/ERC20Forwarder.sol:ERC20Forwarder \
        --chain {{chain}} --verifier sourcify --watch {{ args }}

# Verify the implementation on etherscan
contracts-verify-impl-etherscan address chain *args:
    cd contracts && forge verify-contract {{address}} \
        src/ERC20Forwarder.sol:ERC20Forwarder \
        --chain {{chain}} --verifier etherscan --watch {{ args }}

# Verify the implementation on a custom explorer
contracts-verify-impl-custom address chain verifier-url *args:
    cd contracts && forge verify-contract {{address}} \
        src/ERC20Forwarder.sol:ERC20Forwarder \
        --chain {{chain}} --verifier-url {{verifier-url}}  --watch {{ args }}

# Verify the implementation on both sourcify and etherscan
contracts-verify-impl address chain: (contracts-verify-impl-sourcify address chain) (contracts-verify-impl-etherscan address chain)

# Verify the ERC1967 proxy on sourcify (encodes the constructor args from the deploy inputs)
contracts-verify-proxy-sourcify proxy implementation protocol-adapter logic-ref owner chain *args:
    cd contracts && env -u ETHERSCAN_API_KEY forge verify-contract {{proxy}} \
        dependencies/@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
        --chain {{chain}} --verifier sourcify --watch \
        --constructor-args "$(cast abi-encode 'c(address,bytes)' {{implementation}} "$(cast calldata 'initialize(address,bytes32,address)' {{protocol-adapter}} {{logic-ref}} {{owner}})")" {{ args }}

# Verify the ERC1967 proxy on etherscan (encodes the constructor args from the deploy inputs)
contracts-verify-proxy-etherscan proxy implementation protocol-adapter logic-ref owner chain *args:
    cd contracts && forge verify-contract {{proxy}} \
        dependencies/@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
        --chain {{chain}} --verifier etherscan --watch \
        --constructor-args "$(cast abi-encode 'c(address,bytes)' {{implementation}} "$(cast calldata 'initialize(address,bytes32,address)' {{protocol-adapter}} {{logic-ref}} {{owner}})")" {{ args }}

# Verify the ERC1967 proxy on a custom explorer (encodes the constructor args from the deploy inputs)
contracts-verify-proxy-custom proxy implementation protocol-adapter logic-ref owner chain verifier-url *args:
    cd contracts && forge verify-contract {{proxy}} \
        dependencies/@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
        --chain {{chain}} --verifier-url {{verifier-url}}  --watch \
        --constructor-args "$(cast abi-encode 'c(address,bytes)' {{implementation}} "$(cast calldata 'initialize(address,bytes32,address)' {{protocol-adapter}} {{logic-ref}} {{owner}})")" {{ args }}

# Verify the ERC1967 proxy on both sourcify and etherscan
contracts-verify-proxy proxy implementation protocol-adapter logic-ref owner chain: (contracts-verify-proxy-sourcify proxy implementation protocol-adapter logic-ref owner chain) (contracts-verify-proxy-etherscan proxy implementation protocol-adapter logic-ref owner chain)

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

# Lint bindings (clippy)
bindings-lint:
    cd bindings && cargo clippy --no-deps -- -Dwarnings
    cd bindings && cargo clippy --no-deps --tests -- -Dwarnings

# Format bindings
bindings-fmt:
    cargo fmt

# Check bindings formatting
bindings-fmt-check:
    cargo fmt -- --check

# --- All ---

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

# Check formatting for all (contracts + bindings)
all-fmt-check:
    @echo "==> Checking contract formatting..."
    @just contracts-fmt-check
    @echo "==> Checking bindings formatting..."
    @just bindings-fmt-check

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

# Prerequisites check (mirrors CI)
all-check:
    git status
    @echo "==> Checking storage layouts..."
    @just contracts-storage-check
    @echo "==> Static analysis with slither..."
    @just contracts-static-analysis
    @echo "==> Checking formatting..."
    @just all-fmt-check
    @echo "==> Linting..."
    @just all-lint
    @echo "==> Checking bindings are up-to-date..."
    @just bindings-check
