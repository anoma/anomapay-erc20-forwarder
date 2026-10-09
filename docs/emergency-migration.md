# Emergency migration

The draft [`EmergencyMigratingERC20Forwarder`](../contracts/src/draft/EmergencyMigratingERC20Forwarder.sol) keeps the ERC20 forwarder usable after someone finds a flaw in an ERC20 transfer circuit that lets false proofs pass, for example in the circuit code or in the RISC Zero version that it uses ([anoma/dos-pm#42](https://github.com/anoma/dos-pm/issues/42)). This document lists the cases in which the forwarder moves to a new circuit version, says how the resources move in each case, and describes the draft.

## Terms

This document uses the terms of the [glossary](../CONTEXT.md): circuit version, active version, deprecated version, vulnerable logic ref, V1 resource, soft migration and emergency migration.

## Cases

The examples name circuit versions with letters, in release order. Each case starts from the same state:

- **A**: a deprecated version.
- **B**: the active version.
- **C**: the version that the forwarder moves to.
- **D**: the version after C, only in [A second incident](#a-second-incident).

V1 resources carry the logic reference that the V1 forwarder accepts. In the examples, that is A.

### Voluntary upgrade

No circuit version has a flaw. C improves B.

1. The kind tables release C as the active version, and B becomes deprecated. The owner of the protocol adapter stores the new kind table commitment.
2. The owner of the forwarder upgrades it to an implementation that accepts the logic reference of C. The forwarder keeps its address, so the label of its resources does not change.
3. When the backend creates resources of C, the owner of the adapter deprecates the logic reference of B.
4. Owners of resources of A and B, and of V1 resources, soft-migrate them to C.

A voluntary upgrade needs no emergency migration. The regular `ERC20Forwarder` has no function that sets a new logic reference yet; the release that ships C adds one. After an incident, every later implementation must keep the emergency migration, because the resources with a listed logic reference have no other way out. A voluntary upgrade then uses an emergency implementation and calls `reinitialize` with the logic reference of C and an empty list.

### Upgrade after a flaw

Each incident follows these steps:

1. The owner of the protocol adapter pauses it. The adapter then executes no transaction.
2. The owner of the adapter denies each vulnerable logic reference with `denyLogicRefs`: it adds the logic reference to both denylists.
3. The owner of the forwarder upgrades it to `EmergencyMigratingERC20Forwarder` and, in the same call, calls `reinitialize` with the logic reference of C and the vulnerable logic references to list (see [Which resources can emergency-migrate](#which-resources-can-emergency-migrate)). C has no flaw and has the migrate call. Only a circuit with the migrate call can start an emergency migration. If the active version has no migrate call, the forwarder must move to a version that has one, even if the active version has no flaw.
4. The kind tables release C as the active version. They keep a vulnerable version listed as deprecated, but no transaction can use its rows, because the adapter denies its logic reference. The owner of the adapter stores the new kind table commitment. If B has no flaw, the owner deprecates its logic reference.
5. The owner of the adapter unpauses it.
6. Resource owners emergency-migrate their resources with a vulnerable logic reference, and soft-migrate their resources of a deprecated version.

`reinitialize` checks that the adapter denies each listed logic reference on both denylists, and the logic reference of C on neither.

The cases differ in the circuit versions with the flaw:

| Flaw in | C | The adapter denies | `reinitialize` lists | Soft migration | Emergency migration |
| --- | --- | --- | --- | --- | --- |
| B, the active version | fixes B | B | B | A and V1 resources | B |
| A, a deprecated version | adds the migrate call to B | A | A | B | A and V1 resources |
| A and B, for example through a RISC Zero version that both use | fixes A and B | A and B | A and B | none | A, B and V1 resources |

If more deprecated versions have the flaw, the adapter denies each of them, and `reinitialize` lists them too.

### A second incident

After an incident, C is active and has the migrate call. `reinitialize` runs only once per implementation, so each later incident needs an upgrade to a new implementation of the forwarder. If a later flaw is in C, the owner follows the steps above with D, which fixes C. If a later flaw is only in a deprecated version, for example A, C stays active: the owner upgrades the forwarder and calls `reinitialize` with the logic reference of C and the list with A. `reinitialize` can keep the logic reference if it lists at least one logic reference. The logic references of the first incident stay listed, so their resources can still emergency-migrate to the active version.

### Flaws that the forwarder cannot handle

- **A flaw in the RISC Zero verifier or in the compliance circuit.** It lets false proofs pass for every circuit. The owner of the adapter upgrades the adapter to an implementation without the flaw. An emergency migration does not help. If the flaw is in a RISC Zero version that circuit versions of the forwarder also use, the owner also follows the steps above.
- **A flaw in the circuit of another application.** The owner of that application handles it. This forwarder must not list its logic reference (see [Which resources can emergency-migrate](#which-resources-can-emergency-migrate)).

## Emergency migration transactions

An emergency migration transaction consumes one ephemeral resource of the active version, the trigger, and creates resources of the active version for the same total quantity. For each migrated resource, the trigger's logic proves that the commitment tree at a given root contains the resource's commitment, and computes the resource's nullifier. One signature of the resource owner over the action tree root authorizes all resources of the batch, so all of them must have the same authorization key.

The trigger calls the forwarder with `(Migrate, token, total quantity, MigrateEntry[])`, encoded by `encode_migrate_forwarder_input_batch` on the branch `xuyang/batch_migration` of anomapay-erc20-resource. Each entry contains the nullifier, the commitment tree root of the proof, the logic reference of the resource, and the forwarder address in the resource label.

Before it reads the first entry, the forwarder checks that both denylists of the protocol adapter still contain every vulnerable logic reference that it lists. Then, for each entry, it checks that:

- the forwarder address in the resource label is this forwarder or the V1 forwarder of the chain,
- the forwarder lists the logic reference as vulnerable,
- the root is a historical root of the adapter,
- the adapter's nullifier set does not contain the nullifier,
- the forwarder did not migrate the resource before.

The forwarder records each nullifier before it reads the next entry, so a batch that contains one resource two times fails. It emits `Migrated` for each entry. An emergency migration moves no tokens, so an indexer that adds up the `Wrapped` and `Unwrapped` amounts must not count it as a deposit.

## Why any historical root works

The root check ties the resource to the adapter's commitment tree. Without it, a prover could build a Merkle tree around a resource that never existed. Any historical root of the adapter is enough, and the forwarder stores no root of its own:

- After the denial, no transaction can create a resource with the vulnerable logic reference, so no root contains one that an earlier root does not.
- The nullifier checks stop a second use of a resource, whichever root its proof uses.

The backend can therefore prove against the adapter's current root.

## Which resources can emergency-migrate

The forwarder keeps its address when it is upgraded, so the label `hash(forwarder, token)` of its resources is the same for every circuit version. The logic reference is different, and it is part of the resource kind `hash(logicRef, labelRef)`.

The forwarder must emergency-migrate only resources whose tokens it holds, not every resource whose logic reference the adapter denies. So an entry must meet two conditions:

- **The label names this forwarder or the V1 forwarder of the chain.** Anyone can deploy a contract that acts as a forwarder, and a resource with that contract in its label can have any quantity. The forwarder holds the tokens of its own resources and of V1 resources, because the V1 balances moved to it. The implementation takes the V1 forwarder as a constructor argument, or the zero address on a chain without a V1 forwarder. The script that deploys the implementation must take the address from the deployment record, `RecordedDeployments.forwarderV1`.
- **The forwarder lists the logic reference.** `reinitialize` adds the logic references that the owner passes, and nothing removes them. The owner must list only circuit versions of this forwarder and the logic reference of the V1 forwarder. All applications share the denylists: a resource with another application's denied logic reference can have this forwarder's label and any quantity, and an emergency migration of it would create ERC20 resources for tokens that the forwarder does not hold.

A V1 resource needs no check of its logic reference. A resource with the V1 forwarder in its label reaches this adapter only through the copy-in of the v1 state, or through a kind table alias until the adapter deprecates the V1 forwarder's logic reference. Both carry that logic reference. Any other V1 resource needs a flaw, and the same flaw could create resources with this forwarder's label too. Before the completion run unpauses the adapter, its owner deprecates the V1 forwarder's logic reference, so that no transaction creates V1 resources.

The forwarder does not check tokens. The owner lists the V1 forwarder's logic reference only if the V1 balances of all tokens that the V1 forwarder wrapped moved to this forwarder. The migration checklist requires this before the adapter unpauses.

## Why the adapter must deny the vulnerable logic reference

An emergency migration does not consume the resource at the adapter; the forwarder records its nullifier. Without the entry in the denylist for consumed resources, the resource owner could also consume the resource at the adapter, for example to soft-migrate it. A transaction that uses the flaw could also add the nullifier of another owner's resource to the adapter's nullifier set, and that resource could then not emergency-migrate. Without the entry in the denylist for created resources, a transaction that uses the flaw could still create resources with the vulnerable logic reference, and these resources could emergency-migrate too. So the logic reference must be on both denylists: deprecating it, which adds it to the denylist for created resources only, is not enough. The adapter has no function that removes a denylist entry. If an upgrade of the adapter removes one, every emergency migration fails until the owner denies the logic reference again.

## Limits

- **No amount check.** The tokens stay in the forwarder, so the balance check of wrap and unwrap cannot check an emergency migration. The trigger's logic must make sure that the created resources match the migrated resources: the same token, the total quantity, and the owner's signature over the action tree root, which covers the commitments of the created resources. If the logic does not check this, an emergency migration can create resources for tokens that the forwarder does not hold.
- **The owner chooses the list.** The forwarder cannot check on chain that it holds the tokens of the resources with a listed logic reference, and no function removes a listed logic reference (see [Which resources can emergency-migrate](#which-resources-can-emergency-migrate)).
- **Resources that an attacker created or stole can emergency-migrate.** Nobody can tell them from correct resources: resources are private, and a transaction that uses the flaw looks correct on chain. An earlier root would exclude them, but it needs the start of the attack, which is usually unknown, and it would also block every correct resource created after that root. Because nobody can tell the blocked resources apart, their tokens could not be returned fairly either.
- **Soft migration carries a flaw into the active version.** Until the adapter denies a deprecated version with a flaw, resources that an attacker created or stole with the flaw can soft-migrate to the active version. Nobody can tell them from correct resources of the active version.
- **No replacement of withdrawn tokens.** If someone used the flaw to unwrap tokens, the forwarder holds fewer tokens than the resources represent. Unwraps then succeed in the order they execute until the forwarder does not hold enough tokens, and the unwraps after that fail.
- **Consumed resources cannot emergency-migrate.** A resource whose nullifier is in the adapter's nullifier set cannot emergency-migrate. This includes resources whose nullifier an attacker added with the flaw.

## Notes on the draft

- The reinitializer version of each implementation must be one more than the initialized version of the forwarder when the upgrade starts. The draft uses 2, because `ERC20Forwarder.initialize` sets 1. `reinitialize` is owner-only: if an upgrade does not call it in the same call, nobody else can choose the logic reference and the list.
- No script deploys the draft yet.
- The contract declares no initializer of its own. `ERC20Forwarder.initialize` initializes every parent contract, and `reinitialize` must not run it again, so it calls no parent initializer.
- The contract reports the `VERSION` of `ERC20Forwarder`, because a constant cannot be overridden. Before the draft becomes a release, `VERSION` must become a virtual getter.
