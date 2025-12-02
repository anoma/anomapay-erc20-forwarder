[![CI](https://github.com/anoma/Simple-Transfer-Example/actions/workflows/ci.yml/badge.svg)](https://github.com/anoma/Simple-Transfer-Example/actions/workflows/ci.yml)

# Simplified Transfer Example

This repository contains a simplified example of a transfer application built
with Rust, exposed via a JSON api.

The project demonstrates basic transfer functionality with multiple components
organized in a workspace structure.

## Security

If you believe you've found a security issue, we encourage you to notify us via Email
at [security@anoma.foundation](mailto:security@anoma.foundation).

Please do not use the issue tracker for security issues. We welcome working with you to resolve the issue promptly.

## Components

- **Transfer App** (`simple_transfer/transfer_app/`)

  The main application that orchestrates transfers and provides the user interface.

- **Transfer Library** (`simple_transfer/transfer_library/`)

  Contains the core transfer logic and algorithms.

- **Transfer NIF** (`simple_transfer/transfer_nif/`)

  Provides native function bindings for performance-critical operations.

- **Transfer Witness** (`simple_transfer/transfer_witness/`)

  Handles cryptographic proof generation and verification for transfers.

- **Contracts** (`contracts/`)

  Contains the Solidity forwarder contract being called through the EVM protocol adapter.

## Building

To build the entire workspace:

```shell
cargo build
```

## Running

To run the application, some parameters need to be passed via the environment.

| Variable                         | Meaning                                                 | Example                  |
|----------------------------------|---------------------------------------------------------|--------------------------|
| `RPC_URL`                        | URL for Ethereum RPC defining the network               | https://sepolia.drpc.org |
| `GALILEO_INDEXER_ADDRESS`        | URL for the anoma indexer                               | http://example.com       |
| `FEE_PAYMENT_WALLET_PRIVATE_KEY` | The hex encoded private key for the fee payment account | 0x00                     |
| `ALCHEMY_API_KEY`                | Key for Alchemy API services                            | `123456-ABCDEF`          |

To run the application, simply execute `cargo run`.

### Docker

There is a Docker image in the repo to build your own image.

```shell
docker build -t transfer .
```

Run the container as follows. Replace the values as necessary.

```shell
docker run -it --rm -p 8000:8000 transfer
```

## Contracts

### Prerequisites

Get an up-to-date version of [Foundry](https://github.com/foundry-rs/foundry) with

```sh
curl -L https://foundry.paradigm.xyz | sh
foundryup
```

### Usage

#### Build

Change the directory to the `contracts` folder with `cd contracts` and run

```sh
forge build
```

#### Tests & Coverage

To run the tests, run

```sh
forge test
```

To show the coverage report, run

```sh
forge coverage
```

Append the

- `--no-match-coverage "(script|test|draft)"` to exclude scripts, tests, and drafts,
- `--report lcov` to generate the `lcov.info` file that can be used by code review tooling.

#### Linting & Static Analysis

As a prerequisite, install the

- `solhint` linter (see https://github.com/protofire/solhint)
- `slither` static analyzer (see https://github.com/crytic/slither)

To run the linter and static analyzer, run

```sh
npx solhint --config .solhint.json 'src/**/*.sol' && \
npx solhint --config .solhint.other.json 'script/**/*.sol' 'test/**/*.sol' && \
slither .
```

#### Documentation

Run

```sh
forge doc
```

#### Deployment

To simulate deployment on sepolia, run

```sh
forge script script/DeployERC20Forwarder.s.sol:DeployERC20Forwarder \
  --sig "run(bool,address,bytes32,address)" <IS_TEST_DEPLOYMENT> <PROTOCOL_ADAPTER> <CARRIER_LOGIC_REF> <EMERGENCY_COMMITTEE> \
  --rpc-url sepolia
```

Append the

- `--broadcast` flag to deploy on sepolia
- `--verify --slow` flags for subsequent contract verification on Etherscan (`--slow` adds 15 seconds of waiting time
  between verification attempts)
- `--account <ACCOUNT_NAME>` flag to use a previously imported keystore (see `cast wallet --help` for more info)

#### Block Explorer Verification

For post-deployment verification on Etherscan run

```sh
forge verify-contract \
   <ADDRESS> \
   src/ERC20Forwarder.sol:ERC20Forwarder \
   --chain sepolia
```

after replacing `<ADDRESS>` with the respective contract address.
