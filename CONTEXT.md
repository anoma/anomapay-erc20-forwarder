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
`crates/bindings/deployments.json` — the proxy address of each environment on each chain, plus the genesis fields pinning how that address was derived. Written once per chain at its first deploy and never edited; what an environment currently runs is read from the chain, not from here.

## Note on upstream names

`transfer_library`, `transfer_witness`, and the underlying transfer circuit live
in `anoma/anomapay-erc20-resource` and keep those names — they are immutable from
this repo's perspective. Do not propagate "transfer" as the umbrella name into
layers above them (the integration-test crate, scenario setups, helpers); use
"AnomaPay ERC20" there.
