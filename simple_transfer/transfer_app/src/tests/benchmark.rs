#![cfg(test)]

use crate::tests::fixtures::user_with_private_key;
use crate::tests::request::proving::mint::example_mint_transaction;
use crate::user::Keychain;
use crate::{AnomaPayConfig, load_config};
use futures::future::join_all;

/// Create `count` mint transactions concurrently.
///
/// A mint transaction generates 2 logic proofs and 1 compliance proof. If proof
/// aggregation is enabled, there is a fourth proof that is generated after the
/// first 3 proofs have been generated concurrently.
async fn mint(config: &AnomaPayConfig, alice: Keychain, count: i32) {
    let mut i = 0;
    let mut transaction_futures = vec![];
    while i < count {
        let transaction_future = example_mint_transaction(alice.clone(), config);
        transaction_futures.push(transaction_future);
        i += 1;
    }

    let _x = join_all(transaction_futures).await;
}

/// Test that creates `CONCURRENCY` mint transactions concurrently.
/// This test is not supposed to be run each time, so it is ignored.
/// Control concurrency with env var `CONCURRENCY` to determine how many transactions you want to generate at
/// once.
///
/// Run the benchmark with `CONCURRENCY=10 cargo test benchmark_mint -- --include-ignored`
#[ignore]
#[tokio::test]
async fn benchmark_mint() {
    let num: i32 = std::env::var("CONCURRENCY")
        .expect("CONCURRENCY env var must be set to an integer between 1 and i32 max")
        .parse()
        .expect("CONCURRENCY env var must be set to an integer between 1 and i32 max");

    let config = load_config().await.expect("failed to load config in test");
    let alice = user_with_private_key(&config);
    let _ = mint(&config, alice, num).await;
}
