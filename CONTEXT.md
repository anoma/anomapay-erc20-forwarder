# AnomaPay ERC20 Forwarder

The forwarder contract and integration-test layer for **AnomaPay ERC20**: the application that wraps ERC20 tokens on Ethereum into AnomaPay ERC20 resources of the Anoma Resource Machine (ARM), lets value move while shielded, and unwraps back to ERC20.

## Language

**AnomaPay ERC20**:
The application. The umbrella term for the wrap / transfer / unwrap lifecycle of shielded ERC20 value. Use this name (not "transfer") for anything that spans more than the single shielded-to-shielded action — crates, setups, test files, helpers.
_Avoid_: transfer (as an umbrella for the whole app), shielded token

**AnomaPay ERC20 resource**:
A resource that ERC20 tokens in the forwarder back, in place of a plain ERC20 balance. Say "ERC20 resource" after the first mention.
_Avoid_: shielded resource

**Wrap**:
Lock ERC20 tokens and create the ERC20 resources that they back.

**Transfer**:
Move value from ERC20 resources to other ERC20 resources. "Transfer" names *only* this action, never the app.

**Split**:
A transfer that creates more ERC20 resources than it consumes.

**Merge**:
A transfer that consumes more ERC20 resources than it creates.

**Unwrap**:
Consume ERC20 resources and release the ERC20 tokens that back them.

**Protocol adapter**:
The contract that verifies transactions on a chain. When it processes a resource, it makes the external calls of the resource, for example a wrap or an unwrap at the forwarder.

**Commitment tree**:
The Merkle tree of the commitments of all resources, which the protocol adapter keeps. A **historical root** is a root of the commitment tree that the protocol adapter stores.

**Nullifier set**:
The set of the nullifiers of all consumed resources, which the protocol adapter keeps.

**Resource logic**:
The circuit that decides when a transaction can create or consume a resource.

**Logic ref**:
The hash that identifies the code of a resource logic.

**Label ref**:
The hash of the data that separates the resources of one resource logic. For an ERC20 resource, the data are the addresses of the forwarder and the token.

**Value ref**:
For a persistent ERC20 resource, the SHA-256 hash of the authorization key and the encryption key of its owner. For the ephemeral resource of an unwrap, the address of the receiver.

**Action tree root**:
The root of a Merkle tree over the tags of an action, in the order of its list. The tag of a resource is its nullifier if the transaction consumes it, else its commitment.

**App data / Deletion criterion**:
The app data of a resource holds four lists of blobs: the resource payload, the discovery payload, the external payload and the application payload. The deletion criterion of a blob is `Never` or `Immediately`. The protocol adapter emits each blob with `Never` as an event. Each blob of the external payload is an external call, whatever its deletion criterion.

**External call**:
A call that the protocol adapter makes to a forwarder when it processes a resource. The external payload of the resource carries it, and the resource logic proof covers it.

**In-circuit check**:
A check that a circuit makes: a proof of the circuit is valid only if the check holds. For example, the ERC20 resource logic checks the signature of the owner.

**Out-of-circuit check**:
A check outside the circuits, for example a check that the forwarder or the protocol adapter makes on chain.

**Compliance unit / Aggregation proof / Delta proof**:
Each action has one compliance unit. Its compliance proof shows the **compliance checks**: the in-circuit checks that the action follows the rules of the ARM. The aggregation proof aggregates the compliance proofs and the resource logic proofs of a transaction into one proof, so the protocol adapter verifies only the aggregation proof and the delta proof. The delta proof shows that a transaction balances: for each kind base, the consumed and the created quantities are equal.

**Forwarder**:
The contract that the protocol adapter calls for a wrap or an unwrap. It holds the tokens that back the ERC20 resources.

**Environment**:
One of the two ERC20 forwarder deployments the repo maintains, each recorded per chain in the deployment record and tracking a branch. Say "environment" (not "network" or "deployment target") — a chain is where an environment lives, not which one it is.

**Staging / Production**:
The two environments. Staging is owned by the deployment wallet and upgraded directly; production is owned by a Safe multisig whose signers confirm and execute upgrades. Each environment's forwarder accepts calls only from the protocol adapter proxy of the same environment. The branches tracking them keep their own names, `staging` and `main`.

**Promotion**:
Moving a commit unchanged from `next` to `staging`, or from `staging` to `main`. The pull request opening one carries the gate proving the environment it targets runs that commit's source. Changes only ever flow this way.

**Deployment record**:
`crates/bindings/deployments.json` — the proxy address of each environment on each chain, plus the genesis fields pinning how that address was derived, and, under `legacy`, the legacy ERC20 forwarder of each chain that ran a legacy protocol adapter. Written once per chain at its first deploy and never edited; what an environment currently runs is read from the chain, not from here.

**Legacy protocol adapter**:
The immutable protocol adapter that a chain used before the Galileo upgrade.

**Galileo upgrade**:
The replacement of the legacy protocol adapter of a chain with the protocol adapter, once for each chain.

**Migrated chain**:
A chain whose protocol adapter copied the commitment tree and the nullifier set of its legacy protocol adapter.

**Legacy ERC20 forwarder**:
The immutable ERC20 forwarder that ran with a chain's legacy protocol adapter, recorded with the logic ref it accepts. It belongs to no environment.
_Avoid_: V1 forwarder, retired forwarder

**Legacy-forwarder resource**:
A resource whose label ref names the legacy ERC20 forwarder, on a chain that ran a legacy protocol adapter. It carries the logic ref that the legacy ERC20 forwarder accepts. The asset migration moved its tokens to the forwarder.
_Avoid_: V1 resource

**Asset migration**:
The move of the tokens that a chain's legacy ERC20 forwarder holds to the forwarder of one environment, through `LegacyERC20ForwarderMigration`. It changes no resource.
_Avoid_: migration (on its own)

**Circuit version**:
A release of the ERC20 resource logic. Its logic ref identifies its code, and each resource carries the logic ref of its circuit version.

**Logic ref denylist**:
Two lists of logic refs that the protocol adapter keeps, one for created resources and one for consumed resources. To _deprecate_ a logic ref, the owner of the protocol adapter adds it to the list for created resources, so transactions can consume its resources but not create them. To _deny_ it, the owner adds it to both lists.

**Active version**:
The one circuit version that the forwarder accepts. The backend creates its resources.

**Deprecated version**:
Every other circuit version that the kind trees list, as an alias of the active version. The owner of the protocol adapter deprecates its logic ref, so transactions consume its resources but create none.

**Vulnerable logic ref**:
The logic ref of a circuit version with a flaw. The owner of the protocol adapter denies it, so no transaction consumes or creates its resources, and `reinitialize` lists it in the forwarder.

**Kind**:
The hash to curve of the logic ref and the label ref of a resource.

**Kind base**:
The point that the compliance circuit multiplies by the quantity of a resource. Two resources balance against each other only if they have the same kind base.
_Avoid_: kind point

**Kind tree**:
A Merkle tree that gives kinds their kind bases. Two kinds with the same kind base are **aliases**. The protocol adapter stores the root of one kind tree, its **kind tree root**.

**Conversion**:
A transaction that consumes resources of one kind and creates resources of another kind for the same quantity. The kind tree gives both kinds one kind base, so the transaction balances.

**Soft migration**:
The process in which users convert their resources of a deprecated version, and their legacy-forwarder resources, into resources of the active version.
_Avoid_: migration (on its own)

**Hard migration**:
The process in which users create resources of the active version for their resources with a vulnerable logic ref, whose label ref names this forwarder or the legacy ERC20 forwarder. The protocol adapter does not consume the old resources. The forwarder stores their nullifiers instead, and the tokens stay in the forwarder. The contracts and the circuit crates call it emergency migration.
_Avoid_: rescue

## Note on upstream names

`anomapay_erc20_library`, `anomapay_erc20_witness`, and the underlying circuit live in `anoma/anomapay-erc20-resource`. Their types keep the "transfer" names (`TransferLogic`, `TokenTransferWitness`) — they are immutable from this repo's perspective. Do not propagate "transfer" as the umbrella name into layers above them (the integration-test crate, scenario setups, helpers); use "AnomaPay ERC20" there.
