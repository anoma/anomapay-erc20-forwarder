# Emergency migration

The draft [`EmergencyMigratingERC20Forwarder`](../contracts/src/draft/EmergencyMigratingERC20Forwarder.sol) keeps the ERC20 forwarder usable after someone finds a flaw in a RISC Zero version or in the ERC20 resource logic that lets false proofs pass ([anoma/dos-pm#42](https://github.com/anoma/dos-pm/issues/42)). Owners of ERC20 resources with a vulnerable logic reference can then create resources with the new logic reference for the same quantity. A vulnerable logic reference is the logic reference of a circuit with such a flaw; the protocol adapter denies it, and the forwarder replaced it and no longer accepts it. The tokens do not move: the forwarder keeps them.

## Incident procedure

1. The owner of the protocol adapter pauses it. The adapter then executes no transaction.
2. The owner upgrades the protocol adapter to an implementation whose circuit keys and RISC Zero verifier do not have the flaw, and denies the logic reference that the forwarder accepts: it adds it to both logic ref denylists of the adapter, the one for consumed and the one for created resources.
3. The owner of the forwarder upgrades it and calls `reinitialize` with the new logic reference.
4. The owner unpauses the protocol adapter.
5. Resource owners send migration transactions.

`reinitialize` checks that both denylists of the adapter contain the vulnerable logic reference and that neither contains the new one.

## Migration transactions

A migration transaction consumes one ephemeral resource with the new logic reference, the trigger, and creates resources with the new logic reference for the same total quantity. For each migrated resource, the trigger's logic proves that the commitment tree at a given root contains the resource's commitment, and computes the resource's nullifier. One signature of the resource owner over the action tree root authorizes all resources of the batch, so all of them must have the same authorization key.

The trigger calls the forwarder with `(Migrate, token, total quantity, MigrateEntry[])`, encoded by `encode_migrate_forwarder_input_batch` in anomapay-erc20-resource. Each entry contains the nullifier, the commitment tree root of the proof, the vulnerable logic reference, and the forwarder address in the resource label.

Before it reads the first entry, the forwarder checks that both denylists of the protocol adapter still contain every vulnerable logic reference that it replaced. Then, for each entry, it checks that:

- the forwarder address in the resource label is this forwarder,
- the forwarder replaced the logic reference as vulnerable,
- the adapter's root history contains the root,
- the adapter's nullifier set does not contain the nullifier,
- the forwarder did not migrate the resource before.

The forwarder records each nullifier before it reads the next entry, so a batch that contains one resource two times fails. It emits `Migrated` for each entry. A migration moves no tokens, so an indexer that adds up the `Wrapped` and `Unwrapped` amounts must not count it as a deposit.

## Why any root of the adapter works

The root check ties the resource to the adapter's commitment tree. Without it, a prover could build a Merkle tree around a resource that never existed. Any root that the adapter recorded is enough, and the forwarder stores no root of its own:

- After the denial, no transaction can create a resource with the vulnerable logic reference, so no root contains one that an earlier root does not.
- The nullifier checks stop a second use of a resource, whichever root its proof uses.

The backend can therefore prove against the adapter's current root.

## What `reinitialize` stores

The forwarder keeps its address when it is upgraded, so the label `hash(forwarder, token)` is the same for resources with the vulnerable and with the new logic reference. The logic reference is different, and it is part of the resource kind `hash(logicRef, labelRef)`. `reinitialize` reads the current logic reference from storage, adds it to the set of vulnerable logic references, and then writes the new one.

The forwarder must accept only vulnerable logic references that it replaced itself, not every logic reference that the adapter denies. All applications share the denylists. A resource with another application's denied logic reference can have this forwarder's label and any quantity, and migrating it would create ERC20 resources for tokens that the forwarder does not hold.

## Why the adapter must deny the vulnerable logic reference

A migration does not consume the migrated resource at the adapter; the forwarder records its nullifier. Without the entry in the denylist for consumed resources, the resource owner could also consume the resource at the adapter, for example in a transaction that uses a kind table alias to create a resource with the new logic reference from it. A transaction that uses the flaw could also add the nullifier of another owner's resource to the adapter's nullifier set, and that resource could then not migrate. Without the entry in the denylist for created resources, a transaction that uses the flaw could still create resources with the vulnerable logic reference, and these resources could migrate too. So the logic reference must be on both lists: deprecating it, which adds it to the denylist for created resources only, is not enough. The adapter has no function that removes a denylist entry. If an upgrade of the adapter removes one, every migration fails until the owner denies the logic reference again.

## Repeated incidents

`reinitialize` runs once per implementation, so each incident upgrades the forwarder to a new implementation. Its `reinitialize` adds one logic reference to the forwarder's set of vulnerable logic references, and each migration entry names the logic reference of its resource. After a second incident, resources with the first vulnerable logic reference can still migrate.

## Limits

- **No amount check.** The tokens stay in the forwarder, so the balance check of wrap and unwrap cannot check a migration. The forwarder only checks that no tokens move. The trigger's logic must make sure that the created resources match the migrated resources: the same token, the total quantity, and the owner's signature over the action tree root, which covers the commitments of the created resources. If the logic does not check this, a migration can create resources for tokens that the forwarder does not hold.
- **Resources that an attacker created or stole can migrate.** Nobody can tell them from correct resources: resources are private, and a transaction that uses the flaw looks correct on chain. An earlier root would exclude them, but it needs the start of the attack, which is usually unknown, and it would also block every correct resource created after that root. Because nobody can tell the blocked resources apart, their tokens could not be returned fairly either.
- **No replacement of withdrawn tokens.** If someone used the flaw to unwrap tokens, the forwarder holds fewer tokens than the migrated resources represent. Unwraps then succeed in the order they execute until the forwarder does not hold enough tokens, and the unwraps after that fail.
- **Consumed resources cannot migrate.** A resource whose nullifier is in the adapter's nullifier set cannot migrate. This includes resources whose nullifier an attacker added with the flaw.
- **Only this forwarder's label.** An entry whose label contains another forwarder address fails. V1 resources, which the V2 commitment tree contains on chains that ran V1, cannot migrate with this draft.
- **One logic reference per call.** `reinitialize` replaces only the logic reference that the forwarder accepts at that time. A deprecated version that the kind table still aliases is not replaced.

## Notes on the draft

- `reinitialize` uses a fixed reinitializer version, so it runs once per implementation. The version must be one more than the initialized version of the forwarder when the upgrade starts. The draft uses 2, because `ERC20Forwarder.initialize` sets 1. `reinitialize` is also owner-only: if an upgrade does not call it in the same call, nobody else can choose the logic reference.
- The contract declares no initializer of its own. `ERC20Forwarder.initialize` initializes every parent contract, and `reinitialize` must not run it again, so it calls no parent initializer.
- The contract reports the `VERSION` of `ERC20Forwarder`, because a constant cannot be overridden. Before the draft becomes a release, `VERSION` must become a virtual getter.
