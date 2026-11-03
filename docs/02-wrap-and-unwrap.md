# Wrap and Unwrap

This document specifies how the protocol adapter calls the ERC20 forwarder, and what a wrap and an unwrap do. The code is in [`contracts/src/ERC20Forwarder.sol`](../contracts/src/ERC20Forwarder.sol) and [`contracts/src/ERC20ForwarderPermit2.sol`](../contracts/src/ERC20ForwarderPermit2.sol). The glossary [`CONTEXT.md`](../CONTEXT.md#language) defines the terms.

## 1. Resources and calls

An ERC20 resource is persistent or ephemeral. A persistent ERC20 resource stays until a transaction consumes it. An ephemeral ERC20 resource exists only in one transaction, and its external payload carries one call to the forwarder:

- A **wrap** consumes an ephemeral ERC20 resource. Its call takes tokens from their owner.
- An **unwrap** creates an ephemeral ERC20 resource. Its call sends tokens to a receiver.

For a wrap, the transaction also creates ERC20 resources of the same kind point, usually persistent ones. For an unwrap, it also consumes them. Otherwise the transaction does not balance. The kind of an ERC20 resource follows from its logic ref and its label ref. The label ref is the hash of the forwarder address and the token address. An upgrade keeps the address, so it keeps the label refs.

When the protocol adapter processes an ephemeral ERC20 resource, it calls `forwardCall(logicRef, input)` on the forwarder with the logic ref of the resource. The ERC20 resource logic builds the input and the expected output of the call. Its in-circuit checks require that the forwarder and the token of the call are the addresses that the label ref hashes, and that the amount is the quantity of the resource. The resource logic proof covers the call, so a prover cannot change it.

## 2. The call

`forwardCall` makes these out-of-circuit checks before it runs the call:

- The caller is the protocol adapter of the forwarder (`ProtocolAdapterMismatch`).
- The logic ref is the accepted logic ref, which `getLogicRef()` returns (`LogicRefMismatch`).
- No other call of the forwarder runs. A reentrancy guard rejects a second call.

The input starts with three 32-byte words: the call type, the token and the amount, a `uint128`. The data of the call type follow, with a fixed length (`InvalidInputLength`):

| Call type | Data length | Data                                                                                                                       |
| --------- | ----------- | -------------------------------------------------------------------------------------------------------------------------- |
| `Wrap`    | 7 words     | `WrapData`: the Permit2 nonce and deadline, the owner of the tokens, the action tree root, and the signature `r`, `s`, `v` |
| `Unwrap`  | 1 word      | `UnwrapData`: the receiver                                                                                                 |

The forwarder reads its balance of the token before and after the transfer. A wrap reverts with `BalanceMismatch` if the balance does not increase by exactly the amount, and an unwrap if it does not decrease by exactly the amount. A change in the other direction reverts with an arithmetic underflow (`Panic(0x11)`). So the forwarder supports no token that takes a fee on a transfer.

The forwarder returns an empty output. The protocol adapter compares it with the expected output, which the resource logic sets to empty (`ForwarderCallOutputMismatch`). The resource logic gives the call the deletion criterion `Immediately`, so the protocol adapter emits the call only in `ForwarderCallExecuted`, with the input and the output.

## 3. Wrap

The forwarder calls `permitWitnessTransferFrom` of Permit2. Permit2 transfers the amount of the token from the owner to the forwarder only if the owner signed this transfer. The signature covers the token, the amount, the nonce, the deadline, the forwarder as the spender, and the witness `Witness(bytes32 actionTreeRoot)`. Permit2 rejects a used nonce and a passed deadline, and it can transfer the tokens only after the owner approved Permit2 for the token. The forwarder emits `Wrapped(token, from, amount)`.

The in-circuit checks of the ERC20 resource logic require that the action tree root of the input is the action tree root of the action. So the signature authorizes the transfer only for this action. The action tree root covers the resources that the action creates, so the signature also fixes who owns the new ERC20 resources.

## 4. Unwrap

The forwarder sends the amount of the token to the receiver with `safeTransfer` of OpenZeppelin, and it emits `Unwrapped(token, to, amount)`.

The in-circuit checks of the ERC20 resource logic require that the value of the ephemeral resource commits to the receiver. The owner of each consumed persistent ERC20 resource signs the action tree root, which covers the ephemeral resource. So the signature also authorizes the receiver.

## 5. Trust assumptions

- **The forwarder trusts its protocol adapter.** It executes each call of its protocol adapter with the accepted logic ref. The in-circuit checks of the resource logic cover the input of the call.
- **Permit2 checks the authorization of a wrap.** The forwarder does not check the signature of the owner itself.

## 6. Parameters

| Name                                         | Value                                                                                             | Use                                                                         |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `_PERMIT2`                                   | `0x000000000022D473030F116dDEE9F6B43aC78BA3`                                                      | The canonical Permit2 contract, at the same address on all supported chains |
| `ERC20ForwarderPermit2._WITNESS_TYPE_STRING` | `"Witness witness)TokenPermissions(address token,uint256 amount)Witness(bytes32 actionTreeRoot)"` | The witness type of the Permit2 signature                                   |
