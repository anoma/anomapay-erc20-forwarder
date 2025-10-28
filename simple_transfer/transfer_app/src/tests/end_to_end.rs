#[cfg(test)]
mod tests {
    use crate::evm::evm_calls::pa_submit_transaction;
    use crate::examples::end_to_end::burn::create_burn_transaction;
    use crate::examples::end_to_end::generalized_transfer::create_general_transfer_transaction;
    use crate::examples::end_to_end::mint::create_mint_transaction;
    use crate::examples::end_to_end::split::create_split_transaction;
    use crate::examples::end_to_end::transfer::create_transfer_transaction;
    use crate::tests::fixtures::{alice_keychain, bob_keychain};
    use crate::user::Keychain;
    use crate::{load_config, AnomaPayConfig};
    use arm::resource::Resource;
    use arm::transaction::Transaction;
    use serial_test::serial;
    ////////////////////////////////////////////////////////////////////////////
    // Scenarios

    #[tokio::test]
    #[serial]
    /// Create a mint transaction, and then transfer the resource to another user.
    async fn test_mint() {
        let config = load_config().expect("failed to load config in test");
        // create a keychain with a private key
        let alice = alice_keychain(&config);

        // create a test mint transaction for alice
        let (minted_resource, transaction) = create_test_mint_transaction(&config, &alice).await;
        println!("{:?}", minted_resource);
        println!("{:?}", minted_resource.commitment());

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit mint transaction");
    }

    #[tokio::test]
    #[serial]
    /// Create a mint transaction, and then transfer the resource to another user.
    async fn test_mint_and_transfer() {
        let config = load_config().expect("failed to load config in test");
        // create a keychain with a private key
        let alice = alice_keychain(&config);
        let bob = bob_keychain();

        // create a test mint transaction for alice
        let (minted_resource, transaction) = create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit mint transaction");

        // create a test transfer function from bob to alice
        let transaction =
            create_test_transfer_transaction(&config, alice, bob, minted_resource).await;

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit transfer transaction");
    }

    #[tokio::test]
    #[serial]
    /// Create a mint transaction, and then split the resource between the minter and another
    /// person.
    async fn test_mint_and_split() {
        let config = load_config().expect("failed to load config in test");
        // create a keychain with a private key
        let alice = alice_keychain(&config);
        let bob = bob_keychain();

        // create a test mint transaction for alice
        let (minted_resource, transaction) = create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit mint transaction");

        // create a test split transaction function from bob to alice.
        // alice gets 1, and bob gets 1 too.
        let (_resource, _maybe_remainder_resource, transaction) =
            create_test_split_transaction(&config, &alice, &bob, minted_resource, 1).await;

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit split transaction");
    }

    #[tokio::test]
    #[serial]
    /// Create a mint transaction, and then split the resource so that none remains.
    async fn test_mint_and_split_defaults_to_transfer() {
        let config = load_config().expect("failed to load config in test");
        // create a keychain with a private key
        let alice = alice_keychain(&config);
        let bob = bob_keychain();

        // create a test mint transaction for alice
        let (minted_resource, transaction) = create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit mint transaction");

        // create a test split transaction function from bob to alice.
        // alice does not get anything, bob gets 2.
        let (_resource, maybe_remainder_resource, transaction) =
            create_test_split_transaction(&config, &alice, &bob, minted_resource, 2).await;

        match maybe_remainder_resource {
            Some(_remainder) => {
                panic! {"Some remains after transfer!"}
            }
            None => {
                pa_submit_transaction(transaction)
                    .await
                    .expect("failed to submit split transaction");
            }
        }
    }

    #[tokio::test]
    #[serial]
    /// Create a mint trson. Burn tansaction, and then split the resource between the minter and another
    /// perhe remainder resource afterward.
    async fn test_mint_and_split_and_burn() {
        let config = load_config().expect("failed to load config in test");
        // create a keychain with a private key
        let alice = alice_keychain(&config);
        let bob = bob_keychain();

        // create a test mint transaction for alice
        let (minted_resource, transaction) = create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit mint transaction");

        // create a test split transaction from bob to alice
        let (_resource, maybe_remainder_resource, transaction) =
            create_test_split_transaction(&config, &alice, &bob, minted_resource, 1).await;

        match maybe_remainder_resource {
            Some(remainder_resource) => {
                pa_submit_transaction(transaction)
                    .await
                    .expect("failed to submit split transaction");

                // create a burn transfer for alice's remainder resource.
                let transaction =
                    create_test_burn_transaction(&config, &alice, remainder_resource).await;

                pa_submit_transaction(transaction)
                    .await
                    .expect("failed to submit burn transaction");
            }
            None => {
                panic! {"No resource to burn from split!"}
            }
        }
    }

    #[tokio::test]
    #[serial]
    /// Create two mint transactions, and then split the resource between the minter and another
    /// person.
    async fn test_mint_and_generalized_split() {
        let config = load_config().expect("failed to load config in test");
        // create a keychain with a private key
        let alice = alice_keychain(&config);
        let bob = bob_keychain();

        // create test mint transactions for alice
        let (first_minted_resource, first_transaction) =
            create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(first_transaction)
            .await
            .expect("failed to submit first mint transaction");

        // Alice now has 2

        let (second_minted_resource, second_transaction) =
            create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(second_transaction)
            .await
            .expect("failed to submit second mint transaction");

        // Alice now has 4

        // create a test split transaction function from alice to bob.
        // alice gets 1, and bob gets 3.
        let (_resource, maybe_remainder_resource, transaction) =
            create_test_generalized_transfer_transaction(
                &alice,
                Some(bob),
                vec![first_minted_resource, second_minted_resource],
                3,
                &config,
            )
            .await;

        match maybe_remainder_resource {
            Some(_remainder) => {
                pa_submit_transaction(transaction)
                    .await
                    .expect("failed to submit general split transaction");
            }
            None => {
                panic! {"None remaining from generalized transfer!"}
            }
        }
    }

    #[tokio::test]
    #[serial]
    /// Create two mint transactions, and then split the resource between the anoma resource and
    /// burn the rest to the sender Ethereum address.
    async fn test_mint_and_generalized_burn() {
        let config = load_config().expect("failed to load config in test");
        // create a keychain with a private key
        let alice = alice_keychain(&config);

        // create test mint transactions for alice
        let (first_minted_resource, first_transaction) =
            create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(first_transaction)
            .await
            .expect("failed to submit first mint transaction");

        // Alice now has 2

        let (second_minted_resource, second_transaction) =
            create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(second_transaction)
            .await
            .expect("failed to submit second mint transaction");

        // Alice now has 4

        // create a test split transaction for alice.
        // alice gets 3 tokens back to her address on Ethereum, and keeps one resource.
        let (_resource, maybe_remainder_resource, transaction) =
            create_test_generalized_transfer_transaction(
                &alice,
                None,
                vec![first_minted_resource, second_minted_resource],
                3,
                &config,
            )
            .await;

        match maybe_remainder_resource {
            Some(_remainder) => {
                pa_submit_transaction(transaction)
                    .await
                    .expect("failed to submit generalized burn transaction");
            }
            None => {
                panic! {"None remaining from generalized transfer!"}
            }
        }
    }

    #[tokio::test]
    #[serial]
    /// Create a mint transaction, and then burn the resource.
    async fn test_mint_and_burn() {
        let config = load_config().expect("failed to load config in test");
        // create a keychain with a private key
        let alice = alice_keychain(&config);

        // create a test mint transaction for alice
        let (minted_resource, transaction) = create_test_mint_transaction(&config, &alice).await;

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit mint transaction");

        // create a test burn transaction
        let transaction = create_test_burn_transaction(&config, &alice, minted_resource).await;

        pa_submit_transaction(transaction)
            .await
            .expect("failed to submit burn transaction");
    }

    ////////////////////////////////////////////////////////////////////////////
    // Helpers

    /// Create a new transfer transaction, transferring the resource from sender to receiver.
    async fn create_test_transfer_transaction(
        config: &AnomaPayConfig,
        sender: Keychain,
        receiver: Keychain,
        resource: Resource,
    ) -> Transaction {
        // create a transfer transaction
        let result =
            create_transfer_transaction(sender.clone(), receiver.clone(), resource, config).await;
        assert!(result.is_ok());

        let (_transferred_resource, transaction) = result.unwrap();
        transaction
    }

    /// Creates a mint transaction for the given keychain and verifies it.
    async fn create_test_mint_transaction(
        config: &AnomaPayConfig,
        minter: &Keychain,
    ) -> (Resource, Transaction) {
        // create the transaction and assert it did not fail.
        let result = create_mint_transaction(minter.clone(), 2, config).await;
        println!("{:?}", result);
        assert!(result.is_ok());

        // assert the created transaction verifies
        let (minted_resource, transaction) = result.unwrap();
        assert!(transaction.clone().verify().is_ok());
        (minted_resource, transaction)
    }

    /// Create a burn tranasction for the given resource.
    async fn create_test_burn_transaction(
        config: &AnomaPayConfig,
        burner: &Keychain,
        resource: Resource,
    ) -> Transaction {
        // create the transaction and assert it did not fail.
        let result = create_burn_transaction(burner.clone(), resource, config).await;
        assert!(result.is_ok());

        // assert the created transaction verifies
        let (_burned_resource, transaction) = result.unwrap();
        assert!(transaction.clone().verify().is_ok());
        transaction
    }

    /// Creates a mint transaction for the given keychain and verifies it.
    async fn create_test_split_transaction(
        config: &AnomaPayConfig,
        sender: &Keychain,
        receiver: &Keychain,
        resource: Resource,
        amount: u128,
    ) -> (Resource, Option<Resource>, Transaction) {
        // create the transaction and assert it did not fail.
        let result =
            create_split_transaction(sender.clone(), receiver.clone(), resource, amount, config)
                .await;
        assert!(result.is_ok());

        // assert the created transaction verifies
        let (sent_resource, maybe_created_resource, transaction) = result.unwrap();
        assert!(transaction.clone().verify().is_ok());
        (sent_resource, maybe_created_resource, transaction)
    }

    /// Creates a transaction which can split from many resources
    async fn create_test_generalized_transfer_transaction(
        sender: &Keychain,
        maybe_receiver: Option<Keychain>,
        to_send_resources: Vec<Resource>,
        amount: u128,
        config: &AnomaPayConfig,
    ) -> (Resource, Option<Resource>, Transaction) {
        let result = create_general_transfer_transaction(
            sender.clone(),
            maybe_receiver,
            to_send_resources,
            amount,
            config,
        )
        .await;

        assert!(result.is_ok());

        // assert the created transaction verifies
        let (sent_resource, maybe_created_resource, transaction) = result.unwrap();
        assert!(transaction.clone().verify().is_ok());
        (sent_resource, maybe_created_resource, transaction)
    }
}
