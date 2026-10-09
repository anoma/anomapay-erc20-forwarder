# AnomaPay ERC20 Forwarder

The forwarder contract and integration-test layer for **AnomaPay ERC20**: the
application that wraps ERC20 tokens on Ethereum into shielded ARM resources, lets
value move while shielded, and unwraps back to ERC20.

## Language

**AnomaPay ERC20**:
The application. The umbrella term for the wrap / transfer / unwrap lifecycle of
shielded ERC20 value. Use this name (not "transfer") for anything that spans more
than the single shielded-to-shielded action — crates, setups, test files,
helpers.
_Avoid_: transfer (as an umbrella for the whole app), shielded token

**Shielded resource**:
An ERC20 token's value represented as an ARM resource, no longer held as a plain
ERC20 balance.

**Wrap**:
Lock an ERC20 token and create the corresponding shielded resource.

**Transfer**:
Move value from one shielded resource to another — the shielded-to-shielded
action. "Transfer" names *only* this action, never the app.

**Unwrap**:
Consume a shielded resource and release the underlying ERC20 token.

**Forwarder**:
The EVM contract through which the protocol adapter drives ERC20 state changes
(wrap/unwrap) on behalf of AnomaPay ERC20 actions.

**Environment**:
One of the two ERC20 forwarder deployments the repo maintains, each recorded per chain in the deployment record and tracking a branch. Say "environment" (not "network" or "deployment target") — a chain is where an environment lives, not which one it is.

**Staging / Production**:
The two environments. Staging is owned by the deployment wallet and upgraded directly; production is owned by a Safe multisig whose signers confirm and execute upgrades. Each environment's forwarder settles through the protocol adapter proxy of the same environment. The branches tracking them keep their own names, `staging` and `main`.

**Promotion**:
Moving a commit unchanged from `next` to `staging`, or from `staging` to `main`. The pull request opening one carries the gate proving the environment it targets runs that commit's source. Changes only ever flow this way.

**Deployment record**:
`crates/bindings/deployments.json` — the proxy address of each environment on each chain, plus the genesis fields pinning how that address was derived, and the immutable ERC20 forwarder of each chain that ran an immutable protocol adapter. Written once per chain at its first deploy and never edited; what an environment currently runs is read from the chain, not from here.

**Immutable protocol adapter**:
The protocol adapter of a chain before its protocol adapter proxy: one immutable contract per chain. It is stopped, and its state is copied into the protocol adapter proxy.
_Avoid_: v1 protocol adapter

**Immutable ERC20 forwarder**:
The ERC20 forwarder that ran with a chain's immutable protocol adapter: one immutable contract, recorded with the logic ref it accepts. It belongs to no environment.
_Avoid_: V1 forwarder, retired forwarder, legacy forwarder

**Immutable-forwarder resource**:
A resource with the immutable ERC20 forwarder's address in its label. It carries the logic ref that the immutable ERC20 forwarder accepts, and its tokens moved to the forwarder.
_Avoid_: V1 resource

**Circuit version**:
A release of the ERC20 transfer circuit. Its logic ref identifies its code, and each resource carries the logic ref of its circuit version.

**Active version**:
The one circuit version that the forwarder accepts. The backend creates its resources.

**Deprecated version**:
Every other circuit version that the kind tables list, as an alias of the active version. The owner of the protocol adapter deprecates its logic ref, so transactions consume its resources but create none.

**Vulnerable logic ref**:
The logic ref of a circuit version with a flaw. The owner of the protocol adapter denies it, so no transaction consumes or creates its resources, and `reinitialize` lists it in the forwarder.

**Soft migration**:
A transaction that consumes resources of a deprecated version and creates resources of the active version for the same quantity. The kind table makes the two kinds aliases, so the transaction balances.
_Avoid_: conversion

**Emergency migration**:
A transaction that creates resources of the active version for resources with a vulnerable logic ref and this forwarder or the immutable ERC20 forwarder in their label. The adapter does not consume the old resources; the forwarder records their nullifiers, and the tokens stay in the forwarder.
_Avoid_: hard migration, rescue

## Note on upstream names

`transfer_library`, `transfer_witness`, and the underlying transfer circuit live
in `anoma/anomapay-erc20-resource` and keep those names — they are immutable from
this repo's perspective. Do not propagate "transfer" as the umbrella name into
layers above them (the integration-test crate, scenario setups, helpers); use
"AnomaPay ERC20" there.
