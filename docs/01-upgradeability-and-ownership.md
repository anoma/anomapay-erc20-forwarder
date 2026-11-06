# Upgradeability and Ownership

This document specifies the ERC20 forwarder after its deployment: the proxy, its owners, its upgrades and the controls for a flaw. The [overview](./README.md) lists the other documents, and the glossary [`CONTEXT.md`](../CONTEXT.md#language) defines the terms.

## 1. Contracts and owners

The ERC20 forwarder is an ERC-1967 proxy in the UUPS pattern, with the implementation `ERC20Forwarder`. It inherits `ForwarderBaseUpgradeable` from the package `anoma-forwarder-bases`.

- **Proxy.** It keeps its address, its storage and its tokens in each upgrade. CREATE2 gives it an address that depends on the salt of its environment and on its deployment code.
- **Storage.** The proxy stores its protocol adapter, which is the protocol adapter of the same environment, and its accepted logic ref. Both are in the ERC-7201 namespace `anoma.storage.ForwarderBase`. So a later implementation can add storage at other locations.
- **Upgrade.** `_authorizeUpgrade` allows only the owner. `upgradeToAndCall` sets a new implementation and can call a function of it in the same chain transaction.

| Environment | Owner                                                              |
| ----------- | ------------------------------------------------------------------ |
| Staging     | The deployment wallet `0x61462bE56782568376f9cB069382EFa72764a407` |
| Production  | The FWD Safe `0xc703402252Ce1251aa07e0815D50060d27fdd6C4`          |

The deployment record, [`crates/bindings/deployments.json`](../crates/bindings/deployments.json), lists the proxy of each environment on each chain.

## 2. A new logic ref

**`reinitializeLogicRef(newLogicRef)`** replaces the accepted logic ref. Only the owner can call it, and it runs at most once on a proxy for each implementation. The new logic ref must not be zero and must be on no denylist of the protocol adapter. The upgrade scripts call it with `Parameters.LOGIC_REF` in the same chain transaction as the upgrade. No function replaces the protocol adapter. After the replacement, the forwarder rejects calls with the old logic ref, and users convert their resources of the old version ([`03-soft-migration.md`](./03-soft-migration.md)).

## 3. Controls for a flaw

The forwarder acts only when its protocol adapter calls it. So a pause of the protocol adapter also stops the forwarder.

| Flaw in                                                               | Controls                                                                                                                     |
| --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| The code of the ERC20 forwarder                                       | The pause of the protocol adapter, and an upgrade of the forwarder                                                           |
| A version of the ERC20 resource logic                                 | A hard migration ([`04-hard-migration.md`](./04-hard-migration.md))                                                          |
| The protocol adapter, its circuits or the RISC Zero verifier contract | An upgrade of the protocol adapter                                                                                           |
| A RISC Zero zkVM release                                              | An upgrade of the protocol adapter, and a hard migration of each version of the ERC20 resource logic built with that release |

## 4. Trust assumptions

- **The owner upgrades only to reviewed code and sets only reviewed logic refs.** An upgrade replaces all code, and the forwarder wraps and unwraps tokens only for resources with the accepted logic ref. So the owner can change how tokens leave the forwarder. In production, the FWD Safe signers decide each upgrade and each logic ref.
- **The PA Safe and the FWD Safe respond to a flaw in time.** In production, the PA Safe pauses the protocol adapter, and the FWD Safe upgrades the forwarder.
- **The owner transfers the ownership only to a correct address.** `transferOwnership` and `renounceOwnership` come unchanged from OpenZeppelin, and a transfer completes in one step. Nobody can undo a transfer to a wrong address, and after a renouncement nobody can upgrade the forwarder.

## 5. Parameters

| Name                               | Value                                                     | Use                                                                     |
| ---------------------------------- | --------------------------------------------------------- | ----------------------------------------------------------------------- |
| `Parameters.PROXY_SALT_STAGING`    | `"ERC20ForwarderProxyStaging"`                            | CREATE2 salt of the staging proxies                                     |
| `Parameters.PROXY_SALT_PRODUCTION` | `"ERC20ForwarderProxyProduction"`                         | CREATE2 salt of the production proxies                                  |
| `Parameters.IMPLEMENTATION_SALT`   | `"ERC20ForwarderImpl"`                                    | CREATE2 salt of the implementations, in both environments               |
| `Parameters.LOGIC_REF`             | In [`Parameters.sol`](../contracts/script/Parameters.sol) | The logic ref that a new proxy accepts and that the upgrade scripts set |
| `Parameters.DEPLOYMENT_WALLET`     | `0x61462bE56782568376f9cB069382EFa72764a407`              | Owner of the staging proxies                                            |
| `Parameters.FWD_MULTISIG`          | `0xc703402252Ce1251aa07e0815D50060d27fdd6C4`              | The FWD Safe, owner of the production proxies                           |
