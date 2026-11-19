# ERC20 Forwarder

This folder specifies the ERC20 forwarder of AnomaPay. The glossary of this repository, [`CONTEXT.md`](../CONTEXT.md#language), defines the terms.

## 1. Summary

The ERC20 forwarder holds the tokens that back the ERC20 resources. Its protocol adapter calls it with two call types: a wrap takes tokens from their owner through Permit2, and an unwrap sends tokens to a receiver. The forwarder accepts calls only from its protocol adapter, and only with the logic ref of the active version of the ERC20 resource logic. It is an ERC-1967 proxy. Its owner, the deployment wallet in staging and the FWD Safe in production, can upgrade it.

A release of a new version of the ERC20 resource logic changes the accepted logic ref, and users convert their old resources in a soft migration. After a flaw in a version, users replace its resources in a hard migration. Its implementation is a draft.

## 2. Documents

| Document                                                                     | Content                                                                                                        |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| [`01-upgradeability-and-ownership.md`](./01-upgradeability-and-ownership.md) | The proxy, its owners, its upgrades and the response to a flaw                                                 |
| [`02-contract-and-calls.md`](./02-contract-and-calls.md)                     | How the protocol adapter calls the forwarder, and what a wrap and an unwrap do                                 |
| [`03-soft-migration.md`](./03-soft-migration.md)                             | How users convert their resources of a deprecated version into resources of the active version                 |
| [`04-hard-migration.md`](./04-hard-migration.md)                             | How users replace resources of a version with a flaw. Its implementation is a draft.                           |
| [`05-legacy-erc20-forwarder.md`](./05-legacy-erc20-forwarder.md)             | How the ERC20 forwarder differs from the legacy ERC20 forwarder                                                |
| [`06-asset-migration.md`](./06-asset-migration.md)                           | The move of the tokens of the legacy ERC20 forwarder, and the soft migration of the legacy-forwarder resources |

The commands are in [`RELEASE_CHECKLIST.md`](../RELEASE_CHECKLIST.md) and [`MIGRATION_CHECKLIST.md`](../MIGRATION_CHECKLIST.md).
