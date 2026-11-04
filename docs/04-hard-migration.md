# Hard Migration (Draft)

**Status: draft.** No script deploys it, and no environment uses it. Section [7](#7-status-of-the-draft) lists the open points.

This document specifies the hard migration of ERC20 resources, which the code calls emergency migration. It uses two drafts: the forwarder implementation [`EmergencyMigratingERC20Forwarder`](../contracts/src/draft/EmergencyMigratingERC20Forwarder.sol) and the emergency-migrating ERC20 circuit of anoma/anomapay-erc20-resource. The glossary [`CONTEXT.md`](../CONTEXT.md#language) defines the terms.

## 1. Mechanism

A flaw in a circuit, or in its RISC Zero version, can let the protocol adapter accept false proofs. The logic ref of such a version is a **vulnerable logic ref**. After such a flaw, each user replaces their resources of that version, and no tokens move.

1. The owner of the protocol adapter denies the vulnerable logic ref, so no transaction can consume or create its resources. For a deprecated logic ref, the owner adds only the entry for consumed resources, because a second entry for created resources reverts with `LogicRefAlreadyDenied`.
2. A hard migration transaction consumes an ephemeral resource of the new version, the **trigger**. Its in-circuit checks cover a **batch** of old resources of one user and one token, and it makes one external call of the type `Migrate`.
3. The forwarder makes out-of-circuit checks of each old resource against the protocol adapter, and it stores its nullifier. The transaction creates resources of the new version for the total quantity.

Resources of a deprecated version without the flaw convert to the new version in a soft migration ([`03-soft-migration.md`](./03-soft-migration.md)).

## 2. The forwarder

`EmergencyMigratingERC20Forwarder` is an `ERC20Forwarder` with a third call type, `Migrate`. Its constructor stores the legacy ERC20 forwarder of the chain, `LEGACY_FORWARDER()`, or zero on a chain without one.

**`reinitialize(newLogicRef, vulnerableLogicRefs)`** runs at most once on a proxy, and only the owner can call it. The new logic ref must not be zero and must be on no denylist of the protocol adapter. The list must not be empty, and each listed logic ref must occur once and be on both denylists. The function sets the accepted logic ref and stores the list. No function removes a listed logic ref.

**The `Migrate` call** carries the token, the total quantity and one `MigrateEntry` for each old resource: its nullifier, its commitment tree root, its logic ref, and the forwarder address in its label ref. The forwarder first checks that both denylists still contain each listed logic ref. Then it requires for each entry:

- the forwarder address is this forwarder or `LEGACY_FORWARDER` (`UnknownForwarder`),
- the forwarder lists the logic ref (`LogicRefNotVulnerable`),
- the root is a historical root of the protocol adapter (`NonExistingRoot`),
- the nullifier set of the protocol adapter does not contain the nullifier (`ResourceAlreadyConsumed`),
- the forwarder did not store the nullifier before (`ResourceAlreadyMigrated`).

It stores each nullifier before it reads the next entry, so a resource cannot occur twice in a batch. It emits `Migrated` for each entry. It does not check the quantity.

Each later implementation must keep the call type `Migrate` and the storage at `anoma.storage.EmergencyMigratingERC20Forwarder`. Otherwise, users cannot migrate their remaining resources, or a resource can migrate twice.

## 3. The circuit

The emergency-migrating ERC20 circuit wraps, transfers and unwraps like the active version, and it adds the migrate call. For each old resource, it requires a persistent resource whose value ref matches the keys of its owner, with the authorization key of the first resource. It calculates the nullifier and the commitment tree root of the resource. It requires that the label ref is the hash of the forwarder address of the entry and the token of the trigger. For the batch, it requires a total equal to the quantity of the trigger, and one signature over the action tree root. The action tree root covers the new resources, so the signature also selects who receives them.

No in-circuit check compares the roots with stored roots, checks the logic refs, or checks whether a nullifier is used. The out-of-circuit checks of the forwarder cover these values.

## 4. Which resources can hard-migrate

The forwarder must replace only resources that its tokens back:

- **The label ref names this forwarder or the legacy ERC20 forwarder.** Anyone can deploy a contract that acts as a forwarder, and its resources can have any quantity. After the asset migration, this forwarder holds the tokens that back the legacy-forwarder resources.
- **The forwarder lists the logic ref.** All applications share the denylists. So the owner lists only versions of the ERC20 resource logic, and the legacy logic ref only after a complete asset migration.

The forwarder does not check that a legacy-forwarder resource carries the legacy logic ref. It accepts each listed logic ref with either forwarder address. The owner of the protocol adapter deprecates the legacy logic ref before the first transaction, so legacy-forwarder resources come only from the copy of the state. Any other legacy-forwarder resource needs a flaw, and that flaw can also forge resources of this forwarder.

A consumed resource cannot hard-migrate, also when an attacker consumed it with the flaw. A hard migration also does not replace unwrapped tokens: after an attack, unwraps succeed in the order of execution until the tokens run out.

## 5. Why both denylists

A deprecation is not sufficient. The vulnerable logic ref must be on both denylists of the protocol adapter:

- **The list for consumed resources.** Without it, a user can also consume a migrated resource through the protocol adapter, and the flaw can add the nullifier of another user's resource.
- **The list for created resources.** Without it, the flaw can still create resources that can hard-migrate.

The forwarder checks the denials in each `Migrate` call, so it refuses all hard migrations if an upgrade of the protocol adapter removes a denial.

## 6. Roots and forged resources

The commitment tree only grows, and after the denial no transaction adds an old resource. The nullifier checks prevent a second migration, whichever root a proof uses. So any historical root works. The root check is necessary: without it, a prover can build a Merkle tree for a resource that does not exist.

A flaw can let an attacker forge old resources, and the state cannot show the difference to correct ones. A root from before an attack would also exclude the correct resources of later transactions, and the start of an attack is usually unknown. So forged resources can hard-migrate too.

## 7. Status of the draft

- The kind trees do not list the emergency-migrating circuit yet.
- `reinitialize` uses `reinitializer(2)`. After a release that runs a reinitializer of version 2, the draft needs a higher version number.
- If the owner does not call `reinitialize` in the upgrade transaction, each `Migrate` call reverts.
- On a chain with a legacy ERC20 forwarder, an implementation with a zero `LEGACY_FORWARDER` rejects all legacy-forwarder resources. An upgrade to an implementation with the correct address repairs this.
- `VERSION` is a constant of `ERC20Forwarder`. Before a release, it must become a function that each implementation can override.
- `construct_migrate_tx` in `anomapay_emergency_migrating_erc20_library/src/migrate_tx.rs` (anomapay-erc20-resource `v2.0.0-rc.4`) makes a separate Groth16 proof for the compliance unit and for each resource logic, and no aggregation proof. The protocol adapter executes only transactions with an aggregation proof, so it cannot execute a transaction of this builder. The test [`emergency_migration.rs`](../crates/integration-test/tests/emergency_migration.rs) builds hard migration transactions with one aggregation proof, and the protocol adapter executes them.
- `construct_migrate_tx` proves the trigger against a root that its caller passes, for example the latest root. Any historical root works for the trigger.

## 8. Trust assumptions

- **The in-circuit checks cover the quantities.** The balance check of wrap and unwrap, an out-of-circuit check, does not apply, because no tokens move.
- **The owner lists only logic refs of resources that the tokens in the forwarder back.** The forwarder cannot check that it holds the tokens that back their resources.

## 9. Parameters

| Name                                            | Value                                                     | Use                                                     |
| ----------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------- |
| `ANOMAPAY_EMERGENCY_MIGRATING_ERC20_CIRCUIT_ID` | In the crate `anomapay_emergency_migrating_erc20_library` | Logic ref of the emergency-migrating circuit            |
| Signature domain                                | `TokenTransferAuthorizationEmergencyMigrating`            | Domain of the signature over the action tree root       |
| Storage namespace                               | `anoma.storage.EmergencyMigratingERC20Forwarder`          | ERC-7201 location of the list and the stored nullifiers |
