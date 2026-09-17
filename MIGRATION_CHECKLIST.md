# Migration Checklist

How to move the tokens a chain's V1 forwarder holds to the V2 forwarder of one environment. A chain without a V1 forwarder skips all of this. The plan in `anoma-knowledge-base/galileo-v2-transition-and-versioning.md` sets out the whole move, and the pa-evm [`MIGRATION_CHECKLIST.md`](https://github.com/anoma/pa-evm/blob/next/MIGRATION_CHECKLIST.md) moves the protocol adapter state. This file covers the forwarder's part, which is step 5 of the pa-evm checklist.

## How it works

The V1 forwarder is immutable, and only its emergency path can move its tokens. Its emergency committee, the forwarder multisig `0xc703402252Ce1251aa07e0815D50060d27fdd6C4` (`Parameters.FWD_MULTISIG`), assigns an emergency caller with `setEmergencyCaller`. With `forwardEmergencyCall`, that caller sends the forwarder any call the v1 protocol adapter can send, such as an unwrap of any amount to any address. V1 accepts both calls only once its v1 protocol adapter is stopped. It accepts one emergency caller and keeps it.

So the committee assigns a contract, not an account. [`ERC20ForwarderMigration`](./contracts/src/migration/ERC20ForwarderMigration.sol) fixes the V1 forwarder and the V2 forwarder of one environment at deployment, and sets its owner. Its owner-only `migrate` unwraps the full V1 balance of each listed token to the V2 forwarder, and reverts unless V1 keeps none of the token and the V2 forwarder receives exactly that amount. Every listed token emits `ERC20TokenMigrated`, with a zero amount if V1 held none. The caller assignment cannot be undone, but it fixes only where the tokens can go: the owner can move a token that an earlier run left out, and only to the same V2 forwarder.

Two scripts do the work, and both take their addresses and salt from [`Parameters.sol`](./contracts/script/Parameters.sol). [`DeployERC20ForwarderMigration`](./contracts/script/migration/DeployERC20ForwarderMigration.s.sol) deploys the migration contract, makes the deployment wallet `0x61462bE56782568376f9cB069382EFa72764a407` (`Parameters.DEPLOYMENT_WALLET`) its owner in both environments, and proposes the caller assignment to the committee Safe as the deployment wallet. It deploys with CREATE2, so the address commits to both forwarders and the owner: the proposal names the right contract before the deployment lands, and a repeated run finds the contract instead of deploying a second one. [`MigrateERC20ForwarderAssets`](./contracts/script/migration/MigrateERC20ForwarderAssets.s.sol) moves the tokens as the deployment wallet and checks the result. It reads the migration contract from the emergency caller of V1. Both scripts read the two forwarders from [`RecordedDeployments`](./contracts/generated/RecordedDeployments.sol) and check them against the chain: the environment's proxy owner owns the V2 forwarder, and each forwarder forwards for the protocol adapter that the records of the `anoma-pa-evm` package name for it. They also check the migration contract: it holds the recorded forwarders, the deployment wallet owns it, and the owner of the v1 protocol adapter has stopped it.

The move must end while the protocol adapter proxy is still paused. The kind table on that proxy carries V1 members, which let a V1 resource unwrap from the V2 forwarder. A paused proxy executes nothing, so no V1 resource can unwrap before the V2 forwarder holds the V1 tokens.

`IS_PRODUCTION` selects the environment whose V2 forwarder receives the tokens, and every migration recipe reads it. After the caller assignment, the tokens can move only to the V2 forwarder that the migration contract holds, so choose the environment before the proposal.

> [!NOTE]
> Forge 1.8.3 scripts panic on forks of OP-stack chains such as Base. On those chains, append `--network ethereum` to every recipe below. It also sends the CREATE2 deployment through the deterministic deployer, which forge skips on those chains otherwise.

## Before any chain

- [ ] Check that the `v1` array of [`deployments.json`](./crates/bindings/deployments.json) records the chain's V1 forwarder. The scripts refuse a chain without it.

- [ ] Deploy the V2 forwarder of the environment and record it, as for a chain new to an environment in [`RELEASE_CHECKLIST.md`](./RELEASE_CHECKLIST.md). The deploy script and the migration scripts read its protocol adapter from the records of the `anoma-pa-evm` package, so the package must record the protocol adapter proxy that pa-evm deployed for the migration.

- [ ] List the tokens the V1 forwarder wrapped. Read its `Wrapped(address indexed token, address indexed from, uint128 amount)` events from its deployment block, and collect the distinct tokens. Read them from the chain: the backend's token list misses tokens that V1 wrapped. A token that V1 holds but never wrapped stays out of the list, because no V1 resource represents it.

- [ ] Check that the chain's section in the kind tables' [`tokens.json`](https://github.com/anoma/risc0-kind-tables/blob/next/crates/kind-tables/data/tokens.json) lists every token of that list, before pa-evm generates the chain's kind table. The generator writes V1 members only for the tokens listed there. A wrapped token that is missing gets no V1 member, and its V1 resources lose their only way to unwrap.

## Per chain

These steps are step 5 of the pa-evm checklist: they run after the v1 stop and before the completion run. Users cannot transact in that time. The deploy script refuses to run before the stop, because V1 accepts the caller assignment only after it. Agree on a signing time with the committee's signers before the stop.

The pa-evm migration run sends its transactions from the deployment wallet, and so do steps 3 and 7 and a kind table update in step 1. Send those only after that run has ended. The other steps can run while it copies the state.

1. [ ] Read the `Wrapped` events again, up to the block of the stop. The v1 protocol adapter executes no transaction after the stop, so this list is final. If it has a token that `tokens.json` does not list, add the token, regenerate the kind table, and install the new commitment on the protocol adapter proxy while it is still paused. Then export the list:

   ```sh
   export TOKENS='[<TOKEN>,<TOKEN>]'
   ```

2. [ ] Simulate the deployment and the proposal. The simulation executes the caller assignment as the Safe:

   ```sh
   export IS_PRODUCTION=<true|false>
   just contracts-simulate-migration <CHAIN>
   ```

   Besides the checks in [How it works](#how-it-works), it requires that V1 has no emergency caller yet.

3. [ ] Deploy the migration contract and propose the caller assignment to the committee Safe:

   ```sh
   just contracts-deploy-migration deployer <CHAIN>
   ```

   The deployment wallet signs the proposal, so it must be an owner or a delegate of the committee Safe. Export the address the run reports:

   ```sh
   export MIGRATION_ADDRESS=<ADDRESS>
   ```

4. [ ] Verify the migration contract on sourcify and Etherscan, so that the Safe signers can read the source of the contract they assign:

   ```sh
   just contracts-verify $MIGRATION_ADDRESS src/migration/ERC20ForwarderMigration.sol:ERC20ForwarderMigration <CHAIN>
   ```

   and check that the verification worked (e.g. on https://sourcify.dev/#/lookup).

5. [ ] Ask the signers of `0xc703402252Ce1251aa07e0815D50060d27fdd6C4` to confirm and execute the queued transaction in the [Safe app](https://app.safe.global/home?safe=0xc703402252Ce1251aa07e0815D50060d27fdd6C4), once the migration contract is deployed and verified. They can read `FORWARDER_V1()`, `FORWARDER_V2()` and `owner()` on it. The caller assignment cannot be undone. Once executed, confirm it:

   ```sh
   cast call <FORWARDER_V1> "getEmergencyCaller()(address)" --rpc-url <CHAIN>
   ```

6. [ ] Simulate the move:

   ```sh
   just contracts-simulate-migration-move "$TOKENS" <CHAIN>
   ```

   A token with a zero V1 balance still gets a zero-value transfer. If such a token rejects zero-value transfers, the whole move reverts. Then pass the move a list without that token, because it has nothing to move. Keep `$TOKENS` whole for the check.

7. [ ] Run it:

   ```sh
   just contracts-execute-migration deployer "$TOKENS" <CHAIN>
   ```

   The move is one transaction, so a revert moves nothing. To move a token later, run the move again with only the tokens still to move.

8. [ ] Check the result, reading from the chain:

   ```sh
   just contracts-check-migration "$TOKENS" <CHAIN>
   ```

   It checks that the emergency caller of V1 is the migration contract between the recorded forwarders, and that V1 holds none of the tokens. The `ERC20TokenMigrated` events record the amounts the V2 forwarder received.

9. [ ] Continue with step 6 of the pa-evm checklist. Its completion run unpauses the protocol adapter proxy, and V1 resources can then unwrap from the V2 forwarder.
