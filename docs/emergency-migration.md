# Emergency migration

The draft [`MigratingERC20Forwarder`](../contracts/src/draft/MigratingERC20Forwarder.sol) keeps the ERC20 forwarder usable after someone finds a flaw in a RISC Zero version or in the ERC20 resource logic that lets false proofs pass ([anoma/dos-pm#42](https://github.com/anoma/dos-pm/issues/42)). Owners of ERC20 resources with a retired logic reference can then create resources with the new logic reference for the same quantity. A retired logic reference is one that the forwarder no longer accepts. The tokens do not move: the forwarder keeps them.

## Incident procedure

1. The owner of the protocol adapter pauses it. The adapter then executes no transaction.
2. The owner upgrades the protocol adapter to an implementation whose circuit keys and RISC Zero verifier do not have the flaw, and adds the logic reference that the forwarder accepts to the adapter's logic ref denylist.
3. The owner of the forwarder upgrades it and calls `reinitialize` with the new logic reference.
4. The owner unpauses the protocol adapter.
5. Resource owners send migration transactions.

`reinitialize` checks that the adapter denies the retired logic reference and does not deny the new one.

## Migration transactions

A migration transaction consumes one ephemeral resource with the new logic reference, the trigger, and creates resources with the new logic reference for the same total quantity. For each migrated resource, the trigger's logic proves that the commitment tree at a given root contains the resource's commitment, and computes the resource's nullifier. One signature of the resource owner over the action tree root authorizes all resources of the batch, so all of them must have the same authorization key.

The trigger calls the forwarder with `(Migrate, token, total quantity, MigrateEntry[])`, encoded by `encode_migrate_forwarder_input_batch` in anomapay-erc20-resource. Each entry contains the nullifier, the commitment tree root of the proof, the retired logic reference, and the forwarder address in the resource label.

For each entry, the forwarder checks that:

- the forwarder address in the resource label is this forwarder,
- the forwarder retired the logic reference,
- the adapter's root history contains the root,
- the protocol adapter still denies the logic reference,
- the adapter's nullifier set does not contain the nullifier,
- the forwarder did not migrate the resource before.

The forwarder records each nullifier before it reads the next entry, so a batch that contains one resource two times fails. It emits `Migrated` for each entry. A migration moves no tokens, so an indexer that adds up the `Wrapped` and `Unwrapped` amounts must not count it as a deposit.

## Why any root of the adapter works

The root check ties the resource to the adapter's commitment tree. Without it, a prover could build a Merkle tree around a resource that never existed. Any root that the adapter recorded is enough, and the forwarder stores no root of its own:

- After the denial, no transaction can create a resource with the retired logic reference, so no root contains one that an earlier root does not.
- The nullifier checks stop a second use of a resource, whichever root its proof uses.

The backend can therefore prove against the adapter's current root.

## What the rotation stores

The forwarder keeps its address when it is upgraded, so the label `hash(forwarder, token)` is the same for resources with the retired and with the new logic reference. The logic reference is different, and it is part of the resource kind `hash(logicRef, labelRef)`. `reinitialize` reads the current logic reference from storage, adds it to the set of retired logic references, and then writes the new one.

The forwarder must accept only logic references that it retired itself, not every logic reference that the adapter denies. All applications share the denylist. A resource with another application's denied logic reference can have this forwarder's label and any quantity, and migrating it would create ERC20 resources for tokens that the forwarder does not hold.

## Why the adapter must deny the retired logic reference

A migration does not consume the retired resource at the adapter; the forwarder records its nullifier. Without the denylist entry, the resource owner could also consume the resource at the adapter, for example in a transaction that uses a kind table alias to create a resource with the new logic reference from it. A transaction that uses the flaw could also add the nullifier of another owner's resource to the adapter's nullifier set, and that resource could then not migrate. The adapter has no function that removes a denylist entry. If an upgrade of the adapter removes one, every migration of that logic reference fails.

## Repeated incidents

Each rotation adds one logic reference to the forwarder's set of retired logic references, and each migration entry names the logic reference of its resource. After a second rotation, resources with the first retired logic reference can still migrate. One contract thus covers V1 to V2, V1 to V3 and V2 to V3.

## Limits

- **No amount check.** The tokens stay in the forwarder, so the balance check of wrap and unwrap cannot check a migration. The forwarder only checks that no tokens move. The trigger's logic must make sure that the created resources match the migrated resources: the same token, the total quantity, and the owner's signature over the action tree root, which covers the commitments of the created resources. If the logic does not check this, a migration can create resources for tokens that the forwarder does not hold.
- **Resources that an attacker created can migrate.** The forwarder cannot tell resources that an attacker created with the flaw from resources of correct transactions. An earlier root would exclude them, but also every correct resource created after that root. It would also help little: by the time someone finds the flaw, the attacker has probably already unwrapped tokens with such resources.
- **No replacement of withdrawn tokens.** If someone used the flaw to unwrap tokens, the forwarder holds fewer tokens than the migrated resources represent. Unwraps then succeed in the order they execute until the forwarder does not hold enough tokens, and the unwraps after that fail.
- **Consumed resources cannot migrate.** A resource whose nullifier is in the adapter's nullifier set cannot migrate. This includes resources whose nullifier an attacker added with the flaw.
- **Only this forwarder's label.** An entry whose label contains another forwarder address fails. V1 resources, which the V2 commitment tree contains on chains that ran V1, cannot migrate with this draft.
- **One logic reference per rotation.** A rotation retires only the logic reference that the forwarder accepts at that time. A deprecated version that the kind table still aliases is not retired.

## Notes on the draft

- The contract declares no initializer of its own. `ERC20Forwarder.initialize` initializes every parent contract, and a rotation must not run it again, so `reinitialize` calls no parent initializer.
- The contract reports the `VERSION` of `ERC20Forwarder`, because a constant cannot be overridden. Before the draft becomes a release, `VERSION` must become a virtual getter.
- `ILogicRefDenylist` in `src/draft/` declares the one protocol adapter function that the draft reads. Replace it with the pa-evm interface when a pa-evm release contains it.
