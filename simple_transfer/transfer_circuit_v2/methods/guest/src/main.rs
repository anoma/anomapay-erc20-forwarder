use transfer_witness_v2::LogicCircuit;
use transfer_witness_v2::SimpleTransferWitnessV2;
use risc0_zkvm::guest::env;

fn main() {
    let witness: SimpleTransferWitnessV2 = env::read();

    let instance = witness.constrain().unwrap();

    env::commit(&instance);
}
