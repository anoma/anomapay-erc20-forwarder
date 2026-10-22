# AnomaPay ERC20 Forwarder

The forwarder contract and integration-test layer for **AnomaPay ERC20**: the application that wraps ERC20 tokens on Ethereum into shielded ARM resources, lets value move while shielded, and unwraps back to ERC20.

## Language

**AnomaPay ERC20**:
The application. The umbrella term for the wrap / transfer / unwrap lifecycle of shielded ERC20 value. Use this name (not "transfer") for anything that spans more than the single shielded-to-shielded action — crates, setups, test files, helpers.
_Avoid_: transfer (as an umbrella for the whole app), shielded token

**Shielded resource**:
An ERC20 token's value represented as an ARM resource, no longer held as a plain ERC20 balance.

**Wrap**:
Lock an ERC20 token and create the corresponding shielded resource.

**Transfer**:
Move value from one shielded resource to another — the shielded-to-shielded action. "Transfer" names *only* this action, never the app.

**Unwrap**:
Consume a shielded resource and release the underlying ERC20 token.

**Forwarder**:
The EVM contract through which the protocol adapter drives ERC20 state changes (wrap/unwrap) on behalf of AnomaPay ERC20 actions.

**Environment**:
One of the two ERC20 forwarder deployments the repo maintains, each recorded per chain in the deployment record and tracking a branch. Say "environment" (not "network" or "deployment target") — a chain is where an environment lives, not which one it is.

**Staging / Production**:
The two environments. Staging is owned by the deployment wallet and upgraded directly; production is owned by a Safe multisig whose signers confirm and execute upgrades. Each environment's forwarder settles through the protocol adapter proxy of the same environment. The branches tracking them keep their own names, `staging` and `main`.

**Promotion**:
Moving a commit unchanged from `next` to `staging`, or from `staging` to `main`. The pull request opening one carries the gate proving the environment it targets runs that commit's source. Changes only ever flow this way.

**Deployment record**:
`crates/bindings/deployments.json` — the proxy address of each environment on each chain, plus the genesis fields pinning how that address was derived, and, under `legacy`, the legacy ERC20 forwarder of each chain that ran a legacy protocol adapter. Written once per chain at its first deploy and never edited; what an environment currently runs is read from the chain, not from here.

**Legacy ERC20 forwarder**:
The immutable ERC20 forwarder that ran with a chain's legacy protocol adapter, recorded with the logic ref it accepts. It belongs to no environment.
_Avoid_: V1 forwarder, retired forwarder

**Legacy-forwarder resource**:
A resource whose label ref names the legacy ERC20 forwarder, on a chain that ran a legacy protocol adapter. It carries the logic ref that the legacy ERC20 forwarder accepts. The asset migration moved its tokens to the forwarder.
_Avoid_: V1 resource

**Asset migration**:
The one-time move of the tokens that a chain's legacy ERC20 forwarder holds to the forwarder of one environment, through `LegacyERC20ForwarderMigration`. It changes no resource.
_Avoid_: migration (on its own)

**Circuit version**:
A release of the ERC20 transfer circuit. Its logic ref identifies its code, and each resource carries the logic ref of its circuit version.

**Active version**:
The one circuit version that the forwarder accepts. The backend creates its resources.

**Deprecated version**:
Every other circuit version that the kind tables list, as an alias of the active version. The owner of the protocol adapter deprecates its logic ref, so transactions consume its resources but create none.

**Vulnerable logic ref**:
The logic ref of a circuit version with a flaw. The owner of the protocol adapter denies it, so no transaction consumes or creates its resources, and `reinitialize` lists it in the forwarder.

**Conversion**:
A transaction that consumes resources of one kind and creates resources of another kind for the same quantity. The kind table assigns both kinds one kind point, so the transaction balances.

**Soft migration**:
The process in which users convert their resources of a deprecated version, and their legacy-forwarder resources, into resources of the active version.
_Avoid_: migration (on its own)

**Hard migration**:
The process in which users create resources of the active version for their resources with a vulnerable logic ref, whose label ref names this forwarder or the legacy ERC20 forwarder. The protocol adapter does not consume the old resources. The forwarder stores their nullifiers instead, and the tokens stay in the forwarder. The contracts and the circuit crates call it emergency migration.
_Avoid_: rescue

## Note on upstream names

`anomapay_erc20_library`, `anomapay_erc20_witness`, and the underlying circuit live in `anoma/anomapay-erc20-resource`. Their types keep the "transfer" names (`TransferLogic`, `TokenTransferWitness`), and so does the `transfer_library` crate of the legacy circuit — they are immutable from this repo's perspective. Do not propagate "transfer" as the umbrella name into layers above them (the integration-test crate, scenario setups, helpers); use "AnomaPay ERC20" there.
