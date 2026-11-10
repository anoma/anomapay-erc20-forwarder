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

`ERC20Forwarder` has no function that changes the accepted logic ref or the protocol adapter. So a new version of the ERC20 resource logic needs an upgrade to an implementation that sets the new logic ref. That implementation must let only the owner set it, in the same chain transaction as the upgrade. Otherwise, after an upgrade without the call, any account can set a logic ref that it controls and unwrap any amount. The test contract [`ERC20ForwarderUpgradeExample`](../contracts/test/examples/ERC20ForwarderUpgradeExample.sol) shows such an implementation. After the upgrade, the forwarder rejects calls with the old logic ref, and users convert their resources of the old version ([`03-soft-migration.md`](./03-soft-migration.md)).

## 3. Controls for a flaw

The forwarder acts only when its protocol adapter calls it, and only for a resource with the accepted logic ref. So two controls of the protocol adapter can also stop the forwarder:

- **The pause.** The protocol adapter executes no transaction until its owner lifts the pause.
- **The denylists.** The protocol adapter keeps two denylists of logic refs: one for consumed resources and one for created resources. No function removes an entry.
  - To _deprecate_ a logic ref, the owner of the protocol adapter adds it to the list for created resources. Transactions can still consume its resources, but no transaction can create one. So its resources can convert into resources of the active version ([`03-soft-migration.md`](./03-soft-migration.md)).
  - To _deny_ a logic ref, the owner adds it to both lists. No transaction can consume or create its resources, so they cannot convert. Only a hard migration replaces them ([`04-hard-migration.md`](./04-hard-migration.md)).

The owner deprecates the logic ref of a version only after the forwarder accepts another version. A deprecation of the accepted logic ref stops each unwrap, because an unwrap creates the resource that makes its call. It also stops each wrap and each transfer, because the owner deprecates or denies each other version.

| Flaw in                                                               | Controls                                                                                                                                                           |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| The code of the ERC20 forwarder                                       | The pause of the protocol adapter until an upgrade of the forwarder. A denial of the accepted logic ref also stops the flaw, but then each user must hard-migrate. |
| A version of the ERC20 resource logic                                 | The denial of its logic ref, and a hard migration                                                                                                                  |
| The protocol adapter, its circuits or the RISC Zero verifier contract | An upgrade of the protocol adapter                                                                                                                                 |
| A RISC Zero zkVM release                                              | An upgrade of the protocol adapter, the denial of each version of the ERC20 resource logic built with that release, and a hard migration                           |

## 4. Trust assumptions

- **The owner upgrades only to reviewed code.** An upgrade replaces all code, so the owner can change how tokens leave the forwarder. In production, the FWD Safe signers decide each upgrade.
- **The PA Safe and the FWD Safe respond to a flaw in time.** In production, the PA Safe pauses the protocol adapter and denies logic refs, and the FWD Safe upgrades the forwarder.
- **The owner transfers the ownership only to a correct address.** `transferOwnership` and `renounceOwnership` come unchanged from OpenZeppelin, and a transfer completes in one step. Nobody can undo a transfer to a wrong address, and after a renouncement nobody can upgrade the forwarder.

## 5. Parameters

| Name                               | Value                                                     | Use                                                                                                |
| ---------------------------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `Parameters.PROXY_SALT_STAGING`    | `"ERC20ForwarderProxyStaging"`                            | CREATE2 salt of the staging proxies                                                                |
| `Parameters.PROXY_SALT_PRODUCTION` | `"ERC20ForwarderProxyProduction"`                         | CREATE2 salt of the production proxies                                                             |
| `Parameters.IMPLEMENTATION_SALT`   | `"ERC20ForwarderImpl"`                                    | CREATE2 salt of the implementations, in both environments                                          |
| `Parameters.LOGIC_REF`             | In [`Parameters.sol`](../contracts/script/Parameters.sol) | The logic ref that a new proxy accepts. A proxy keeps its logic ref until an upgrade sets another. |
| `Parameters.DEPLOYMENT_WALLET`     | `0x61462bE56782568376f9cB069382EFa72764a407`              | Owner of the staging proxies                                                                       |
| `Parameters.FWD_MULTISIG`          | `0xc703402252Ce1251aa07e0815D50060d27fdd6C4`              | The FWD Safe, owner of the production proxies                                                      |
