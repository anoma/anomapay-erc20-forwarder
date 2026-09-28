# Emergency migration

The draft [`MigratingERC20Forwarder`](../contracts/src/draft/MigratingERC20Forwarder.sol) keeps the ERC20 forwarder usable after someone finds a flaw in a RISC Zero version or in the ERC20 resource logic that lets false proofs pass ([anoma/dos-pm#42](https://github.com/anoma/dos-pm/issues/42)). Owners of ERC20 resources with a retired logic reference can then create resources with the new logic reference for the same quantity. A retired logic reference is one that the forwarder no longer accepts. The tokens do not move: the forwarder keeps them.

## Incident procedure

1. The owner of the protocol adapter pauses it. The adapter then executes no transaction.
2. The owner upgrades the protocol adapter to an implementation whose circuit keys and RISC Zero verifier do not have the flaw, and adds the logic reference that the forwarder accepts to the adapter's logic ref denylist.
3. The owner of the forwarder upgrades it and calls `reinitialize` with the new logic reference and the migration root.
4. The owner unpauses the protocol adapter.
5. Resource owners send migration transactions.

`reinitialize` checks that the adapter is paused, that the adapter's root history contains the migration root, that the adapter denies the retired logic reference, and that the adapter does not deny the new one.

## Migration transactions

A migration transaction consumes one ephemeral resource with the new logic reference, the trigger, and creates resources with the new logic reference for the same total quantity. For each migrated resource, the trigger's logic proves that the commitment tree at the migration root contains the resource's commitment, and computes the resource's nullifier. One signature of the resource owner over the action tree root authorizes all resources of the batch, so all of them must have the same authorization key.

The trigger calls the forwarder with `(Migrate, token, total quantity, MigrateEntry[])`, encoded by `encode_migrate_forwarder_input_batch` in anomapay-erc20-resource. Each entry contains the nullifier, the migration root, the retired logic reference, and the forwarder address in the resource label.

For each entry, the forwarder checks that:

- the forwarder address in the resource label is this forwarder,
- the forwarder retired the logic reference, and the root is the root that it recorded for that logic reference,
- the protocol adapter still denies the logic reference,
- the adapter's nullifier set does not contain the nullifier,
- the forwarder did not migrate the resource before.

The forwarder records each nullifier before it reads the next entry, so a batch that contains one resource two times fails. It emits `Migrated` for each entry. A migration moves no tokens, so an indexer that adds up the `Wrapped` and `Unwrapped` amounts must not count it as a deposit.

## What the rotation stores

The forwarder keeps its address when it is upgraded, so the label `hash(forwarder, token)` is the same for resources with the retired and with the new logic reference. The logic reference is different, and it is part of the resource kind `hash(logicRef, labelRef)`. `reinitialize` stores two values:

- the retired logic reference, which it reads from storage before it writes the new one;
- the migration root. The adapter keeps every root it ever had, but no contract can find the correct one, so the owner supplies it.

## Why the adapter must deny the retired logic reference

A migration does not consume the retired resource at the adapter; the forwarder records its nullifier. Without the denylist entry, the resource owner could also consume the resource at the adapter, for example in a transaction that uses a kind table alias to create a resource with the new logic reference from it. A transaction that uses the flaw could also add the nullifier of another owner's resource to the adapter's nullifier set, and that resource could then not migrate. The adapter has no function that removes a denylist entry. If an upgrade of the adapter removes one, every migration of that logic reference fails.

## Choosing the migration root

The owner chooses the root from the results of the incident investigation. The contract does not check this choice.

- With the latest root, every resource can migrate, also resources that an attacker created with the flaw.
- With an earlier root, no resource created after that root can migrate, also resources from correct transactions.

## Repeated incidents

Each rotation adds one entry to the forwarder's map of retired logic references, and each migration entry names the logic reference of its resource. After a second rotation, resources with the first retired logic reference can still migrate. One contract thus covers V1 to V2, V1 to V3 and V2 to V3.

## Limits

- **No amount check.** The tokens stay in the forwarder, so the balance check of wrap and unwrap cannot check a migration. The forwarder only checks that no tokens move. The trigger's logic must make sure that the created resources match the migrated resources: the same token, the total quantity, and the owner's signature over the action tree root, which covers the commitments of the created resources. If the logic does not check this, a migration can create resources for tokens that the forwarder does not hold.
- **No replacement of withdrawn tokens.** If someone used the flaw to unwrap tokens, the forwarder holds fewer tokens than the migrated resources represent. Unwraps then succeed in the order they execute until the forwarder does not hold enough tokens, and the unwraps after that fail.
- **Consumed resources cannot migrate.** A resource whose nullifier is in the adapter's nullifier set cannot migrate. This includes resources consumed after the migration root, and resources whose nullifier an attacker added with the flaw.
- **Resources created after the migration root cannot migrate.**
- **Only this forwarder's label.** An entry whose label contains another forwarder address fails. V1 resources, which the V2 commitment tree contains on chains that ran V1, cannot migrate with this draft.
- **One logic reference per rotation.** A rotation retires only the logic reference that the forwarder accepts at that time. A deprecated version that the kind table still aliases gets no migration root.

## Notes on the draft

- The contract declares no initializer of its own. `ERC20Forwarder.initialize` initializes every parent contract, and a rotation must not run it again, so `reinitialize` calls no parent initializer.
- The contract reports the `VERSION` of `ERC20Forwarder`, because a constant cannot be overridden. Before the draft becomes a release, `VERSION` must become a virtual getter.
- `ILogicRefDenylist` in `src/draft/` declares the one protocol adapter function that the draft reads. Replace it with the pa-evm interface when a pa-evm release contains it.
