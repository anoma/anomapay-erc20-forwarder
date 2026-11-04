# Asset Migration

This document specifies the asset migration: the move of the tokens of a legacy ERC20 forwarder to the ERC20 forwarder of one environment. It also specifies the soft migration of the legacy-forwarder resources, which these tokens back. Both are parts of the Galileo upgrade of a migrated chain. The glossary [`CONTEXT.md`](../CONTEXT.md#language) defines the terms.

## 1. Purpose

The legacy ERC20 forwarder holds the tokens that back all legacy-forwarder resources. It accepts wrap and unwrap calls from the legacy protocol adapter, which the Galileo upgrade stops. Nothing lifts this stop. After the stop, it also accepts these calls from its emergency caller (section 3). So the tokens move to the ERC20 forwarder, where the kind tree lets each legacy-forwarder resource convert and unwrap (section 2). A chain without a legacy ERC20 forwarder has no asset migration.

## 2. Legacy-forwarder resources

On a migrated chain, the legacy-forwarder resources have the legacy logic ref `bc123236…` and the label ref of the legacy ERC20 forwarder. After the asset migration, the ERC20 forwarder holds the tokens that back them, so the rule R1 of the [soft migration](./03-soft-migration.md) holds. The **legacy-forwarder entries** of the kind tree give each of their kinds the kind point of the kind with the same token, the logic ref of the active version and the label ref of the ERC20 forwarder. The kind trees repository writes these entries for each token that its file `tokens.json` marks with `soft_migrate_from_legacy_forwarder`. Only the tokens that the asset migration moves have this mark.

The owner of the protocol adapter deprecates `bc123236…` before the protocol adapter executes its first transaction. The entries make the kinds aliases in both directions. Without the deprecation, a transaction could convert resources of the ERC20 forwarder into new legacy-forwarder resources. Then:

- the number of legacy-forwarder resources could grow, and the kind tree would have to keep their entries for an unlimited time,
- the hard migration, which accepts each listed logic ref with either forwarder address, could meet legacy-forwarder resources that the copy of the state did not bring.

The ERC20 forwarder accepts another logic ref, so no wrap creates resources with `bc123236…`. After the pause of the protocol adapter ends, each user converts their legacy-forwarder resources when they use them.

A prover proves the consumption of a legacy-forwarder resource with the legacy circuit, whose logic ref is `bc123236…`. This repository keeps its binary in [`legacy-anomapay-erc20-circuit-guest.bin`](../crates/integration-test/elf/legacy-anomapay-erc20-circuit-guest.bin). It takes the witness of the active version.

## 3. The emergency functions of the legacy ERC20 forwarder

Both functions work only while the legacy protocol adapter is stopped (`isEmergencyStopped()`).

- `setEmergencyCaller(caller)`. Only the emergency committee, the FWD Safe, can call it. It accepts one caller and keeps it (`EmergencyCallerAlreadySet`).
- `forwardEmergencyCall(input)`. The emergency caller sends any wrap or unwrap input, without a proof and without a check of the logic ref, for example an unwrap of any amount to any receiver.

So the FWD Safe sets a contract that can send the tokens to one address only, not an account with a private key.

## 4. `LegacyERC20ForwarderMigration`

The constructor stores the legacy ERC20 forwarder (`LEGACY_FORWARDER`), the ERC20 forwarder of one environment (`FORWARDER`) and the owner. It reverts with `InvalidForwarders` if an address is zero or has no code, or if both addresses are the same.

Only the owner can call `migrate(tokens)`, and a reentrancy guard rejects a second call while a call runs. For each token in the list, the function:

1. reads the full balance of the legacy ERC20 forwarder,
2. calls `forwardEmergencyCall` with an unwrap of that balance to `FORWARDER`, in parts of at most `type(uint128).max`, the limit of one unwrap. A zero balance gives one unwrap of zero,
3. reverts with `UnexpectedEmergencyCallOutput` if a call returns data,
4. reverts with `SourceBalanceRemaining` if the legacy ERC20 forwarder still holds some of the token,
5. reverts with `DestinationBalanceMismatch` if `FORWARDER` did not receive exactly that amount,
6. emits `ERC20TokenMigrated(legacyForwarder, forwarder, token, amount)`, also for a zero amount.

A revert for one token moves no token of the call. The owner can call `migrate` again for a token that a call did not include. The token can still go only to `FORWARDER`. The ERC20 forwarder emits no event when it receives the tokens. An indexer that adds up its `Wrapped` and `Unwrapped` amounts must also add the `ERC20TokenMigrated` amounts.

## 5. The list of tokens

The list contains each token of the `Wrapped` events of the legacy ERC20 forwarder, up to the block of the stop. After the stop, the legacy protocol adapter executes no transaction, so this list is final. A token that the legacy ERC20 forwarder holds but never wrapped stays out, because it backs no legacy-forwarder resource.

The kind tree of the chain must have legacy-forwarder entries for each token in the list (section 2). Without the entries, the legacy-forwarder resources of a token cannot unwrap. A token whose balance did not move must have no entries when the protocol adapter starts to execute transactions.

## 6. Staging and production

In both environments, the FWD Safe sets the emergency caller and the deployment wallet owns the migration contract. `IS_PRODUCTION` selects the receiving ERC20 forwarder. The emergency caller cannot change, so the tokens can move to only one environment.

## 7. Trust assumptions

- **The protocol adapter stays paused until the move ends.** Before the move, the ERC20 forwarder does not hold the tokens that back the legacy-forwarder resources, so an unwrap of such a resource would send tokens that back other resources. The ERC20 forwarder sends tokens only when its protocol adapter calls it. No contract checks that the pause lasts until the move ends.
- **The FWD Safe sets the correct migration contract as the emergency caller.** Nobody can undo this step.
- **The owner of the migration contract moves the tokens during the pause.** It selects the tokens and the time, but not the amount or the receiver.
- **The list of tokens is complete.** A token outside the list stays in the legacy ERC20 forwarder until a later `migrate`, and it must have no legacy-forwarder entries until then.
- **No token takes a fee on a transfer.** Otherwise, `migrate` reverts for that token, and the other tokens move without it. Such a token stays in the legacy ERC20 forwarder, so it must have no legacy-forwarder entries.
- **Each token accepts a transfer of zero.** A zero balance gives one unwrap of zero. If the token rejects it, `migrate` reverts, and the other tokens move without it.
- **Each balance moves in one chain transaction.** A balance that needs more unwraps than fit into one chain transaction cannot move. Only a token with a total supply far above `type(uint128).max` can have one.

## 8. Parameters

| Name                                 | Value                                                                             | Use                                                                                       |
| ------------------------------------ | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `Parameters.MIGRATION_SALT`          | `"ERC20ForwarderMigration"`                                                       | CREATE2 salt of the migration contracts                                                   |
| `IS_PRODUCTION`                      | `true` or `false`                                                                 | Environment variable that selects the ERC20 forwarder that receives the tokens            |
| Legacy ERC20 forwarders              | The `legacy` entries of [`deployments.json`](../crates/bindings/deployments.json) | The forwarder of each chain whose tokens move, with its logic ref                         |
| Legacy logic ref                     | `bc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad`                | The logic ref that the legacy ERC20 forwarders accept. Each migrated chain deprecates it. |
| `soft_migrate_from_legacy_forwarder` | `true` or `false` for each token in `tokens.json` of the kind trees repository    | Selects the tokens that get legacy-forwarder entries                                      |
