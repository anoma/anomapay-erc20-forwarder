# Soft Migration

This document specifies the soft migration of ERC20 resources: users replace their resources of a deprecated version with resources of the active version. It states what the kind tree, the ERC20 forwarder and the protocol adapter each add, and what a prover needs. [`06-asset-migration.md`](./06-asset-migration.md) specifies the soft migration of the legacy-forwarder resources. The glossary [`CONTEXT.md`](../CONTEXT.md#language) defines the terms.

## 1. Mechanism

A new version of a resource logic has a new logic ref, so its resources have new kinds. Resources of two kinds balance against each other only if the kind tree gives both kinds one kind base. Then a conversion balances: it consumes old resources and creates new resources for the same quantity.

In this document, the **old version** is the version whose resources users replace, and an **old resource** is a resource of it. The **active version** is the version that the ERC20 forwarder accepts.

A soft migration needs three changes:

1. **The kind tree** gives each kind of the old version the kind base of the kind of the active version with the same label ref.
2. **The ERC20 forwarder** accepts only the logic ref of the active version. So an old resource can unwrap only after a conversion, in an earlier transaction or in the same transaction.
3. **The owner of the protocol adapter deprecates the logic ref of the old version.** Transactions can then consume old resources but not create them.

Each user converts their old resources when they use them. A conversion consumes an old resource, so the protocol adapter verifies a proof of the old version. So the old version must still be trusted. A version with a flaw needs a hard migration ([`04-hard-migration.md`](./04-hard-migration.md)).

The kind trees follow two rules:

- **R1: one forwarder.** Two kinds can share a kind base only if one forwarder holds the tokens that back the resources of both kinds. Otherwise, a user could wrap one token and unwrap another.
- **R2: a way to unwrap.** Each kind with unspent resources keeps a way to unwrap: the forwarder accepts its logic ref, or it shares the kind base of a kind whose logic ref the forwarder accepts.

After the upgrade of the forwarder, a wrap or an unwrap that a prover proved for the old version reverts, and the prover proves it again. After the deprecation, the number of old resources can only decrease. The kind tree keeps their entries while old resources exist (R2).

## 2. What a prover needs

- **The kind tree.** A conversion needs the kind tree whose root the protocol adapter stores. Other transactions can use the empty kind tree, which the protocol adapter always accepts. A proof for another kind tree reverts with `UnacceptedKindTreeRoot`. So a prover uses a new kind tree only after the protocol adapter stores its root.
- **The old circuit.** A prover proves the consumption of a resource with the circuit that its logic ref identifies, and the creation with the circuit of the active version. So the prover keeps the circuit of each old version while its resources can exist.

## 3. Trust assumptions

- **The owner of the protocol adapter denies a flawed version in time.** Until then, a soft migration also converts forged resources: a forged old resource can convert into a resource of the active version that looks correct.
- **The owner of the protocol adapter sets only reviewed kind tree roots.** A wrong kind tree entry lets users take tokens that back other resources. For example, an entry that makes the kinds of two tokens aliases lets a user wrap one token and unwrap the other.
- **Each kind with unspent resources keeps a way to unwrap.** R2 fails if a release removes the entries of a kind while resources of that kind exist.

## 4. Parameters

| Name                   | Value                                                     | Use                                                                                                                             |
| ---------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `Parameters.LOGIC_REF` | In [`Parameters.sol`](../contracts/script/Parameters.sol) | The logic ref that a new ERC20 forwarder accepts ([`01-upgradeability-and-ownership.md`](./01-upgradeability-and-ownership.md)) |
