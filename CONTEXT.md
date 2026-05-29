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

## Note on upstream names

`transfer_library`, `transfer_witness`, and the underlying transfer circuit live
in `anoma/anomapay-erc20-resource` and keep those names — they are immutable from
this repo's perspective. Do not propagate "transfer" as the umbrella name into
layers above them (the integration-test crate, scenario setups, helpers); use
"AnomaPay ERC20" there.
