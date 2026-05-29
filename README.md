[![Contracts Tests](https://github.com/anoma/anomapay-erc20-forwarder/actions/workflows/contracts.yml/badge.svg)](https://github.com/anoma/anomapay-erc20-forwarder/actions/workflows/contracts.yml) [![soldeer.xyz](https://img.shields.io/badge/soldeer.xyz-anomapay--erc20--forwarder-blue?logo=ethereum)](https://soldeer.xyz/project/anomapay-erc20-forwarder) [![License](https://img.shields.io/badge/license-MIT-blue)](https://raw.githubusercontent.com/anoma/anomapay-erc20-forwarder/refs/heads/main/contracts/LICENSE)

[![Crates Tests](https://github.com/anoma/anomapay-erc20-forwarder/actions/workflows/crates.yml/badge.svg)](https://github.com/anoma/anomapay-erc20-forwarder/actions/workflows/crates.yml) [![crates.io](https://img.shields.io/badge/crates.io-anomapay--erc20--forwarder--bindings-blue?logo=rust)](https://crates.io/crates/anomapay-erc20-forwarder-bindings) [![License](https://img.shields.io/badge/license-MIT-blue)](https://raw.githubusercontent.com/anoma/anomapay-erc20-forwarder/refs/heads/main/crates/bindings/LICENSE)

# AnomaPay ERC20 Forwarder

A forwarder contract written in Solidity that enables wrapping and unwrapping of arbitrary ERC20 tokens on the [AnomaPay application](https://anomapay.app/) using the [Anoma EVM protocol adapter](https://github.com/anoma/pa-evm).

## Project Structure

This monorepo is structured as follows:

```
.
├── audits
├── contracts
├── crates
│   ├── bindings
│   └── integration-test
├── Cargo.lock
├── Cargo.toml
├── README.md
└── RELEASE_CHECKLIST.md
```

The [contracts](./contracts/) folder contains the contracts written in [Solidity](https://soliditylang.org/) as well as [Foundry forge](https://book.getfoundry.sh/forge/) tests and deploy scripts.

The [crates](./crates/) folder contains the Rust workspace:

- [bindings](./crates/bindings/) provides [Rust](https://www.rust-lang.org/) bindings for the forwarder contract and exposes its deployment addresses on the different supported networks using the [alloy-rs](https://github.com/alloy-rs) library.
- [integration-test](./crates/integration-test/) contains the Rust integration and e2e tests that deploy the forwarder against a local or forked chain and exercise the wrap / transfer / unwrap lifecycle with risc0-proven transactions.

## Audits

Our software undergoes regular audits:

1. Informal Systems
   - Company Website: https://informal.systems
   - Commit ID: [03e60b64d9dc3845c55e34d1d0bef25392cb5b60](https://github.com/anoma/anomapay-erc20-forwarder/tree/03e60b64d9dc3845c55e34d1d0bef25392cb5b60)
   - Started: 2025-12-01
   - Finished: 2025-12-16
   - Last revised: 2025-12-19

   [📄 Audit Report (pdf)](./audits/2025-12-19_Informal_Systems_AnomaPay_Phase_I.pdf)

## Security

If you believe you've found a security issue, we encourage you to notify us via Email
at [security@anoma.foundation](mailto:security@anoma.foundation).

Please do not use the issue tracker for security issues. We welcome working with you to resolve the issue promptly.
