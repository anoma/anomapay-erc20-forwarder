# Legacy ERC20 Forwarder

This document specifies how the ERC20 forwarder differs from the legacy ERC20 forwarder. The glossary [`CONTEXT.md`](../CONTEXT.md#language) defines the terms of the legacy stack. [`06-asset-migration.md`](./06-asset-migration.md) specifies how the tokens of the legacy ERC20 forwarder move to the ERC20 forwarder.

## 1. Differences

The legacy ERC20 forwarder runs `contracts/v1.0.1` of this repository. It is immutable. Its constructor fixes its protocol adapter, its logic ref and its emergency committee.

| Part                                           | Legacy ERC20 forwarder                                                                                   | ERC20 forwarder                                                                            | Specified in                                                                 |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| Code                                           | Immutable                                                                                                | An ERC-1967 proxy in the UUPS pattern. Its owner can upgrade it.                           | [`01-upgradeability-and-ownership.md`](./01-upgradeability-and-ownership.md) |
| Owner                                          | None. An emergency committee can set one emergency caller after the stop of the legacy protocol adapter. | The deployment wallet in staging, the FWD Safe in production                               | [`01-upgradeability-and-ownership.md`](./01-upgradeability-and-ownership.md) |
| Protocol adapter and logic ref                 | Fixed by the constructor                                                                                 | Stored in the proxy. Only an upgrade can change them.                                      | [`01-upgradeability-and-ownership.md`](./01-upgradeability-and-ownership.md) |
| Wrap, unwrap, balance check, events            | As in `contracts/v1.0.1`                                                                                 | The same                                                                                   | [`02-contract-and-calls.md`](./02-contract-and-calls.md)                     |
| Address                                        | One address for each chain                                                                               | A new address. So the label refs of its resources are new.                                 | [`02-contract-and-calls.md`](./02-contract-and-calls.md)                     |
| Tokens                                         | Holds the tokens that back the legacy-forwarder resources                                                | On a migrated chain, receives these tokens once                                            | [`06-asset-migration.md`](./06-asset-migration.md)                           |
| Versions of the ERC20 resource logic           | One version, logic ref `bc123236…`                                                                       | A release of a new version replaces the active version. Users convert their old resources. | [`03-soft-migration.md`](./03-soft-migration.md)                             |
| Response to a flaw in the ERC20 resource logic | The emergency caller can move all tokens after the stop of the legacy protocol adapter.                  | Users replace their resources of the flawed version (draft)                                | [`04-hard-migration.md`](./04-hard-migration.md)                             |

The interface of the ERC20 forwarder differs in these points:

- `VERSION()` returns a string, in place of `getVersion()`, which returns a `bytes32`.
- The proxy has the functions `owner`, `transferOwnership`, `renounceOwnership`, `upgradeToAndCall`, `proxiableUUID` and `getImplementation`.
- It has no emergency functions (`setEmergencyCaller`, `forwardEmergencyCall`, `getEmergencyCaller`). [`06-asset-migration.md`](./06-asset-migration.md) specifies them.
- Its errors have other names: `ProtocolAdapterMismatch` for `UnauthorizedCaller`, `LogicRefMismatch` for `UnauthorizedLogicRef`, and `ZeroProtocolAdapterNotAllowed` and `ZeroLogicRefNotAllowed` for `ZeroNotAllowed`.
