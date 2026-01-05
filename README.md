[![Contracts & Bindings](https://github.com/anoma/anomapay-backend/actions/workflows/contracts.yml/badge.svg)](https://github.com/anoma/anomapay-backend/actions/workflows/contracts.yml)

[![Rust Lints & Circuits](https://github.com/anoma/anomapay-backend/actions/workflows/rust.yml/badge.svg)](https://github.com/anoma/anomapay-backend/actions/workflows/rust.yml)

[![Webserver & E2E Tests](https://github.com/anoma/anomapay-backend/actions/workflows/rust_test.yml/badge.svg)](https://github.com/anoma/anomapay-backend/actions/workflows/rust_test.yml)

[![AnomaPay Docker](https://github.com/anoma/anomapay-backend/actions/workflows/docker.yml/badge.svg)](https://github.com/anoma/anomapay-backend/actions/workflows/docker.yml)

# Project Structure

This repository is a workspace with the following structure:

```
.
├── benchmark
├── bindings
├── contracts
├── simple_transfer
│   ├── transfer_app
│   ├── transfer_circuit
│   ├── transfer_circuit_v2
│   ├── transfer_library
│   ├── transfer_library_v2
│   ├── transfer_witness
│   └── transfer_witness_v2
└── README.md
```

## Components

- **Benchmark** (`benchmark/`)

  The folder contains a script to compute benchmarks to compare proof generation time for aggregated and non-aggregated AnomaPay ZK proofs.

- **Bindings** (`bindings/`)

  The `bindings` folder makes the contracts and deployments available in [Rust](https://www.rust-lang.org/) using the [`alloy-rs` library](https://github.com/alloy-rs), thus allowing to connect to the ERC20 forwarder contracts on supported networks.

- **Contracts** (`contracts/`)

  The `contracts` folder contains ERC20 forwarder contracts being called through the [EVM protocol adapter](https://github.com/anoma/evm-protocol-adapter) written in [Solidity](https://soliditylang.org/) as well as [Foundry forge](https://book.getfoundry.sh/forge/) tests and deploy scripts.

- **App** (`simple_transfer/transfer_app/`)

  The AnomaPay webserver written in Rust.

- **Circuits** (`simple_transfer/transfer_circuit/` and `simple_transfer/transfer_circuit_v2/`)

  These folders contain helpers to compile the AnomaPay [RISC Zero](https://dev.risczero.com) guest program into an [RISC-V](https://riscv.org/developers/) executable ELF Binaries.

- **Libraries** (`simple_transfer/transfer_library/` and `simple_transfer/transfer_library_v2/`)

  These folder make the ELF Binary and related methods available in Rust.

- **Witnesses** (`simple_transfer/transfer_witness/` and `simple_transfer/transfer_witness_v2/`)

  These folders contain the constraints and methods to provide and convert required witness data for the AnomaPay guest program.

## Security

If you believe you've found a security issue, we encourage you to notify us via Email
at [security@anoma.foundation](mailto:security@anoma.foundation).

Please do not use the issue tracker for security issues. We welcome working with you to resolve the issue promptly.

## Building

To build the entire workspace:

```shell
cargo build
```

## Running

To run the application, some parameters need to be passed via the environment.

| Variable                         | Meaning                                                 | Example                  |
| -------------------------------- | ------------------------------------------------------- | ------------------------ |
| `RPC_URL`                        | URL for the Ethereum RPC defining the network           | https://sepolia.drpc.org |
| `GALILEO_INDEXER_ADDRESS`        | URL for the anoma indexer                               | http://example.com       |
| `FEE_PAYMENT_WALLET_PRIVATE_KEY` | The hex encoded private key for the fee payment account | 0x00                     |
| `ALCHEMY_API_KEY`                | Key for Alchemy API services                            | `123456-ABCDEF`          |
| `BONSAI_API_URL`                 | Bonsai API URL                                          | `http://example.com`     |
| `BONSAI_API_KEY`                 | Bonsai API key                                          | `supersecret`            |

To run the application, simply execute `cargo run`.

### Docker

There is a Docker file in the repo to build your own image of the application.

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
