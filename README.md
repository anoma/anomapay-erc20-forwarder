[![Crates.io](https://img.shields.io/crates/v/anomapay-erc20-forwarder-bindings)](https://crates.io/crates/anomapay-erc20-forwarder-bindings) [![License](https://img.shields.io/crates/l/anomapay-erc20-forwarder-bindings)](https://choosealicense.com/licenses/mit/) [![Contracts Tests](https://github.com/anoma/anomapay-erc20-forwarder/actions/workflows/contracts.yml/badge.svg)](https://github.com/anoma/anomapay-erc20-forwarder/actions/workflows/contracts.yml) [![Bindings Tests](https://github.com/anoma/anomapay-erc20-forwarder/actions/workflows/bindings.yml/badge.svg)](https://github.com/anoma/anomapay-erc20-forwarder/actions/workflows/bindings.yml)

# AnomaPay ERC20 Forwarder

A forwarder contract written in Solidity that enables wrapping and unwrapping of arbitrary ERC20 tokens on the [AnomaPay application](https://anomapay.app/) using the [Anoma EVM protocol adapter](https://github.com/anoma/pa-evm).

## Project Structure

This monorepo is structured as follows:

```
.
├── audits
├── bindings
├── contracts
├── Cargo.lock
├── Cargo.toml
├── README.md
└── RELEASE_CHECKLIST.md
```

The [contracts](./contracts/) folder contains the contracts written in [Solidity](https://soliditylang.org/) as well as [Foundry forge](https://book.getfoundry.sh/forge/) tests and deploy scripts.

The [bindings](./bindings/) folder provides [Rust](https://www.rust-lang.org/) bindings for the conversion of Rust and [RISC Zero](https://risczero.com/) types into [EVM types](https://docs.soliditylang.org/en/latest/types.html) and exposes the deployment addresses on the different supported networks using the [alloy-rs](https://github.com/alloy-rs)
library.

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
