# Release Checklist

Releases of the packages contained in this monorepo follow the [SemVer convention](https://semver.org/spec/v2.0.0.html).

> ![NOTE]
> The `contracts` and `bindings` are independently versioned with `X.Y.Z` and `A.B.C`, respectively.
> Both versions can include release candidates (suffixed with `-rc.?`).

We distinguish between three release cases:

- Deploying a **new** ERC20 forwarder version to multiple new chains resulting in a new
  - `contracts/X.Y.Z` version
  - `bindings/A.0.0` version

- Deploying an **existing** ERC20 forwarder version to multiple new chains resulting in a new
  - `bindings/A.B.0` version

- Maintaining the bindings resulting in a new
  - `bindings/A.B.C` version

## Deploying a new ERC20 Forwarder Version

### 1. Prerequisites

- [ ] Visit https://www.soliditylang.org/ and check that Solidity compiler version used in `contracts/foundry.toml` has no [known vulnerabilities](https://docs.soliditylang.org/en/latest/bugs.html).

- [ ] Install the dependencies with

  ```sh
  just contracts-deps
  ```

- [ ] Check that the dependencies are up-to-date and have no known vulnerabilities in the dependencies

- [ ] Check that the deployer wallet is funded and add it to `cast` with

  ```sh
  cast wallet import deployer --private-key <PRIVATE_KEY>
  ```

  or

  ```sh
  cast wallet import deployer --mnemonic <MNEMONICC>
  ```

- [ ] Set `IS_TEST_DEPLOYMENT` to `false` to deterministically deploy the ERC20 forwarder.

  ```sh
  export IS_TEST_DEPLOYMENT=false
  ```

- [ ] Check that the owner address is set up correctly and export it with

  ```sh
  export OWNER=<ADDRESS>
  ```

- [ ] Set the Alchemy RPC provider by exporting

  ```sh
  export ALCHEMY_API_KEY=<KEY>
  ```

- [ ] Set the Etherscan key

  ```sh
  export ETHERSCAN_API_KEY=<KEY>
  ```

### 2. Bump the Version

- [ ] Bump the version number in the `getVersion()` function in [`./contracts/src/ERC20Forwarder.sol`](./contracts/src/ERC20Forwarder.sol) to the new version number following [SemVer](https://semver.org/spec/v2.0.0.html).

- [ ] Remove all entries from [`./bindings/deployments.json`](./bindings/deployments.json) (replace the array contents with `[]`).

### 3. Test the Contracts

- [ ] Run the test suite with `just contracts-test`

### 4. Deploy and Verify the ERC20 Forwarder

For each chain, you want to deploy to, do the following:

- [ ] **Simulate** the deployment by running

  ```sh
  just contracts-simulate <TOKEN_TRANSFER_CIRCUIT_ID> <CHAIN_NAME> <PROTOCOL_ADAPTER_ADDRESS>
  ```

  where `<TOKEN_TRANSFER_CIRCUIT_ID>` can be found in the [`anoma/anomapay-backend` `transfer_library`](https://github.com/anoma/anomapay-backend/blob/main/simple_transfer/transfer_library/src/lib.rs)
  and `<PROTOCOL_ADAPTER_ADDRESS>` can be found in [`anoma/pa-evm` `bindings/deployments.json`](https://github.com/anoma/pa-evm/blob/main/bindings/deployments.json). **Make sure that you are using the right versions, respectively!**

- [ ] After successful simulation, **deploy** the contract by running

  ```sh
  just contracts-deploy deployer <TOKEN_TRANSFER_CIRCUIT_ID> <CHAIN_NAME> <PROTOCOL_ADAPTER_ADDRESS>
  ```

- [ ] Export the addresses of the newly deployed contracts. The deployment produces **two** contracts: the **proxy**
      (`ERC1967Proxy`) is the ERC20 forwarder address that users interact with and that goes into `deployments.json` (it is
      the returned `erc20ForwarderProxy`), and the **implementation** (`ERC20Forwarder`) is the logic contract the proxy
      delegates to. They must be verified separately, against different sources.

  ```sh
  export PROXY_ADDRESS=<PROXY_ADDRESS>
  export IMPL_ADDRESS=<IMPLEMENTATION_ADDRESS>
  ```

- [ ] Verify the **implementation** (`ERC20Forwarder`)

  ```sh
  just contracts-verify-impl <IMPL_ADDRESS> <CHAIN>
  ```

- [ ] Verify the **proxy** (`ERC1967Proxy`). The recipe encodes the proxy constructor args from these inputs.

  ```sh
  just contracts-verify-proxy <PROXY_ADDRESS> <IMPL_ADDRESS> <PROTOCOL_ADAPTER_ADDRESS> <TOKEN_TRANSFER_CIRCUIT_ID> <OWNER> <CHAIN>
  ```

  Check that the verification worked (e.g., on https://sourcify.dev/#/lookup).

### 5. Update the Deployments Map and Create a new `contracts` and `bindings` GitHub Release

- [ ] Add a deployment entry to [`./bindings/deployments.json`](./bindings/deployments.json) for each chain deployed.

  The `protocolAdapterAddress` records which protocol adapter this forwarder is linked to. No extra tools or scripts are needed — the JSON is embedded at compile time by `addresses.rs`.

- [ ] Change the `bindings` package version number in the [`./bindings/Cargo.toml`](./bindings/Cargo.toml) file to `A.0.0`, where `A` is the last `MAJOR` version number incremented by 1.

- [ ] Clean the bindings build with `just bindings-clean`.

- [ ] Regenerate the bindings with `just contracts-gen-bindings`.

- [ ] Run `just bindings-build` and check that the `Cargo.lock` file reflects the version number change.

- [ ] Run the tests with `just bindings-test`.

- [ ] After merging, create new tags for:
  - [ ] `contracts/X.Y.Z` where `X.Y.Z` must match the ERC20 forwarder version number and
  - [ ] `bindings/A.0.0` tag, where `A` is the last `MAJOR` version incremented by 1.

- [ ] Create new [GH releases](https://github.com/anoma/anomapay-erc20-forwarder/releases) for both packages.

### 6. Publish a new `contracts` package

- [ ] Publish the `contracts` package on https://soldeer.xyz/ with

  ```sh
  just contracts-publish <X.Y.Z> --dry-run
  ```

  where `<X.Y.Z>` is the `_ERC20_FORWARDER_VERSION` number and check the resulting `contracts.zip` file. If everything is correct, remove the `--dry-run` flag and publish the package.

### 7. Publish a new `bindings` package

- [ ] Publish the `anomapay-erc20-forwarder-bindings` package on https://crates.io/ with

  ```sh
  just bindings-publish --dry-run
  ```

  and check the result. If everything is correct, remove the `--dry-run` flag and publish the package.

## Deploying an existing ERC20 Forwarder Version to new Chains

### 1. Prerequisites

- [ ] Visit https://www.soliditylang.org/ and check that Solidity compiler version used in `contracts/foundry.toml` has no known vulnerabilities.

- [ ] Install the dependencies with

  ```sh
  just contracts-deps
  ```

- [ ] Check that the dependencies are up-to-date and have no known vulnerabilities in the dependencies

- [ ] Check that the bindings are up-to-date with

  ```sh
  just bindings-check
  ```

- [ ] Checkout a new git branch branching off from `main`.

- [ ] Check that there are no staged or unstaged changes by running `git status`.

- [ ] Check that the deployer wallet is funded and add it to `cast` with

  ```sh
  cast wallet import deployer --private-key <PRIVATE_KEY>
  ```

  or

  ```sh
  cast wallet import deployer --mnemonic <MNEMONICC>
  ```

- [ ] Set `IS_TEST_DEPLOYMENT` to `false` to deterministically deploy the ERC20 forwarder.

  ```sh
  export IS_TEST_DEPLOYMENT=false
  ```

- [ ] Check that the owner address is set up correctly and export it with

  ```sh
  export OWNER=<ADDRESS>
  ```

- [ ] Set the Alchemy RPC provider by exporting

  ```sh
  export ALCHEMY_API_KEY=<KEY>
  ```

- [ ] Set the Etherscan key
  ```sh
  export ETHERSCAN_API_KEY=<KEY>
  ```

### 2. Build the contracts

- [ ] Run `just contracts-build`

- [ ] Run the test suite with `just contracts-test`

### 3. Deploy and Verify the ERC20 Forwarder

For each **new** chain, you want to deploy to, do the following:

- [ ] **Simulate** the deployment by running

  ```sh
  just contracts-simulate <TOKEN_TRANSFER_CIRCUIT_ID> <CHAIN_NAME> <PROTOCOL_ADAPTER_ADDRESS>
  ```

  where `<TOKEN_TRANSFER_CIRCUIT_ID>` can be found in the [`anoma/anomapay-backend` `transfer_library`](https://github.com/anoma/anomapay-backend/blob/main/simple_transfer/transfer_library/src/lib.rs)
  and `<PROTOCOL_ADAPTER_ADDRESS>` can be found in [`anoma/pa-evm` `deployments.json`](https://github.com/anoma/pa-evm/blob/main/deployments.json). **Make sure that you are using the right versions, respectively!**

- [ ] After successful simulation, **deploy** the contract by running

  ```sh
  just contracts-deploy deployer <TOKEN_TRANSFER_CIRCUIT_ID> <CHAIN_NAME> <PROTOCOL_ADAPTER_ADDRESS>
  ```

- [ ] Export the addresses of the newly deployed contracts. The deployment produces **two** contracts: the **proxy**
      (`ERC1967Proxy`) is the ERC20 forwarder address that users interact with and that goes into `deployments.json` (it is
      the returned `erc20ForwarderProxy`), and the **implementation** (`ERC20Forwarder`) is the logic contract the proxy
      delegates to. They must be verified separately, against different sources.

  ```sh
  export PROXY_ADDRESS=<PROXY_ADDRESS>
  export IMPL_ADDRESS=<IMPLEMENTATION_ADDRESS>
  ```

- [ ] Verify the **implementation** (`ERC20Forwarder`).

  ```sh
  just contracts-verify-impl <IMPL_ADDRESS> <CHAIN>
  ```

- [ ] Verify the **proxy** (`ERC1967Proxy`).

  ```sh
  just contracts-verify-proxy <PROXY_ADDRESS> <IMPL_ADDRESS> <PROTOCOL_ADAPTER_ADDRESS> <TOKEN_TRANSFER_CIRCUIT_ID> <OWNER> <CHAIN>
  ```

  Check that the verification worked (e.g., on https://sourcify.dev/#/lookup).

### 4. Update the Deployments Map and Create a new `bindings` GitHub Release

- [ ] Add a deployment entry to [`./bindings/deployments.json`](./bindings/deployments.json) for each **new** chain deployed.

- [ ] Change the `bindings` package version number in the `./bindings/Cargo.toml` file to `A.B.0`, where `A` is the last `MAJOR` version and `B` is the last `MINOR` version number incremented by 1.

- [ ] Run `just bindings-build` and check that the `Cargo.lock` file reflects the version number change.

- [ ] Run the tests with `just bindings-test`.

- [ ] After merging, create a new `bindings/A.B.0` tag, where `A` is the last `MAJOR` version and `B` is the last `MINOR` version number incremented by 1.

- [ ] Create a new [GH release](https://github.com/anoma/anomapay-erc20-forwarder/releases).

### 5. Publish a new `bindings` package

- [ ] Publish the `anomapay-erc20-forwarder-bindings` package on https://crates.io/ with

  ```sh
  just bindings-publish --dry-run
  ```

  and check the result. If everything is correct, remove the `--dry-run` flag and publish the package.

## Maintaining the Bindings

### 1. Prerequisites

- [ ] Check that the bindings are up-to-date with

  ```sh
  just bindings-check
  ```

- [ ] Checkout a new git branch branching off from `main`.

- [ ] Check that there are no staged or unstaged changes by running `git status`.

### 2. Create a new `bindings` GitHub Release

- [ ] Change the `bindings` package version number in the `./bindings/Cargo.toml` file to `A.B.C`, where `A` and `B` are the last `MAJOR` and `MINOR` version numbers and `C` is the last `PATCH` version number incremented by 1.

- [ ] Run `just bindings-build` and check that the `Cargo.lock` file reflects the version number change.

- [ ] Run the tests with `just bindings-test`.

- [ ] After merging, create a new `bindings/A.B.C` tag, where `A` and `B` are the last `MAJOR` and `MINOR` version numbers, respectively, and `C` is the last `PATCH` version number incremented by 1.

- [ ] Create a new [GH release](https://github.com/anoma/anomapay-erc20-forwarder/releases).

### 3. Publish a new `bindings` package

- [ ] Publish the `anomapay-erc20-forwarder-bindings` package on https://crates.io/ with

  ```sh
  just bindings-publish --dry-run
  ```

  and check the result. If everything is correct, remove the `--dry-run` flag and publish the package.
