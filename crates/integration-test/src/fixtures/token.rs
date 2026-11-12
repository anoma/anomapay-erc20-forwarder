//! Builders of the wraps, transfers and unwraps of one ERC20 token. A builder divides the tokens
//! that its action consumes: each [`ActionBuilder::split`] gives a receiver a fixed share, and the
//! main receiver gets the rest.

use std::cell::Cell;
use std::marker::PhantomData;

use alloy::primitives::{Address, keccak256};
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::chains::chain_id;
use anoma_pa_testkit::commitment_path;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::action::{self, ActionResource};
use anoma_pa_testkit::fixtures::identities::Keychain;
use anoma_pa_testkit::witness::ActionWitnesses;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_witness::calculate_label_ref;
use anyhow::Context;

use crate::fixtures::{ephemeral, persistent};
use crate::state::erc20::erc20_address;
use crate::state::forwarder::erc20_forwarder_address;

/// An ERC20 token and the forwarder that wraps it. It numbers its wraps, and the number gives each
/// wrap its nonce, so a test creates one `Token` per token.
pub struct Token {
    chain_id: u64,
    forwarder: Address,
    address: Address,
    wraps: Cell<u64>,
}

impl Token {
    /// The token that the environment records under `symbol`.
    pub fn new<Env: Environment>(env: &Env, symbol: &str) -> anyhow::Result<Self> {
        Ok(Self {
            chain_id: chain_id(env)?,
            forwarder: erc20_forwarder_address(env)?,
            address: erc20_address(env, symbol)?,
            wraps: Cell::new(0),
        })
    }

    pub fn address(&self) -> Address {
        self.address
    }

    pub fn forwarder(&self) -> Address {
        self.forwarder
    }

    /// A wrap that pulls `quantity` tokens from the account of `payer`, who receives them.
    pub fn wrap(&self, payer: &Keychain, quantity: u128) -> ActionBuilder<FromAccount> {
        self.builder(
            Consumed::Account {
                payer: Box::new(payer.clone()),
                quantity,
                nonce: self.next_wrap_nonce(),
            },
            Some(Receiver::from(payer)),
        )
    }

    /// A transfer of `inputs`, whose total goes to the owner of the first input.
    pub fn transfer(&self, inputs: impl Into<Inputs>) -> ActionBuilder<FromResources> {
        let Inputs(inputs) = inputs.into();
        let main_receiver = inputs.first().map(|(owner, _)| Receiver::from(owner));
        self.builder(Consumed::Resources(inputs), main_receiver)
    }

    /// An unwrap of `inputs`, whose total goes to the account of the owner of the first input.
    pub fn unwrap(&self, inputs: impl Into<Inputs>) -> ActionBuilder<FromResources> {
        let Inputs(inputs) = inputs.into();
        let main_receiver = inputs
            .first()
            .map(|(owner, _)| Receiver::Account(owner.address()));
        self.builder(Consumed::Resources(inputs), main_receiver)
    }

    /// Numbers one more wrap of the token and returns its nonce.
    pub fn next_wrap_nonce(&self) -> [u8; 32] {
        let number = self.wraps.get() + 1;
        self.wraps.set(number);
        keccak256([self.address.as_slice(), &number.to_be_bytes()].concat()).0
    }

    fn builder<Source>(
        &self,
        consumed: Consumed,
        main_receiver: Option<Receiver>,
    ) -> ActionBuilder<Source> {
        ActionBuilder {
            chain_id: self.chain_id,
            forwarder: self.forwarder,
            token: self.address,
            consumed,
            pull: ephemeral::Overrides::default(),
            main_receiver,
            splits: Vec::new(),
            source: PhantomData,
        }
    }
}

/// The persistent resources that an action consumes, each with its owner, who signs for it.
pub struct Inputs(Vec<(Keychain, Resource)>);

impl From<(&Keychain, Resource)> for Inputs {
    fn from((owner, resource): (&Keychain, Resource)) -> Self {
        Self(vec![(owner.clone(), resource)])
    }
}

impl<const N: usize> From<[(&Keychain, Resource); N]> for Inputs {
    fn from(inputs: [(&Keychain, Resource); N]) -> Self {
        Self(
            inputs
                .into_iter()
                .map(|(owner, resource)| (owner.clone(), resource))
                .collect(),
        )
    }
}

impl From<Vec<(&Keychain, Resource)>> for Inputs {
    fn from(inputs: Vec<(&Keychain, Resource)>) -> Self {
        Self(
            inputs
                .into_iter()
                .map(|(owner, resource)| (owner.clone(), resource))
                .collect(),
        )
    }
}

/// A receiver of tokens: an owner gets a persistent resource, and an account gets the tokens
/// released.
#[derive(Clone)]
pub enum Receiver {
    Owner(Box<Keychain>),
    Account(Address),
}

impl From<&Keychain> for Receiver {
    fn from(owner: &Keychain) -> Self {
        Self::Owner(Box::new(owner.clone()))
    }
}

impl From<Address> for Receiver {
    fn from(account: Address) -> Self {
        Self::Account(account)
    }
}

/// The source of a wrap: tokens that Permit2 pulls from an Ethereum account.
pub struct FromAccount;

/// The source of a transfer or an unwrap: persistent resources.
pub struct FromResources;

enum Consumed {
    Account {
        payer: Box<Keychain>,
        quantity: u128,
        nonce: [u8; 32],
    },
    Resources(Vec<(Keychain, Resource)>),
}

/// Builds one action of a [`Token`]. `Source` names where its tokens come from.
pub struct ActionBuilder<Source> {
    chain_id: u64,
    forwarder: Address,
    token: Address,
    consumed: Consumed,
    pull: ephemeral::Overrides,
    main_receiver: Option<Receiver>,
    splits: Vec<(Receiver, u128)>,
    source: PhantomData<Source>,
}

impl<Source> ActionBuilder<Source> {
    /// Makes `receiver` the main receiver, who gets the rest.
    pub fn to(mut self, receiver: impl Into<Receiver>) -> Self {
        self.main_receiver = Some(receiver.into());
        self
    }

    /// Gives `quantity` tokens to `receiver`.
    pub fn split(mut self, receiver: impl Into<Receiver>, quantity: u128) -> Self {
        self.splits.push((receiver.into(), quantity));
        self
    }

    /// The resources of the action in their order: the consumed ones, the main receiver's, then
    /// those of the splits.
    pub fn resources<Env: Environment>(self, env: &Env) -> anyhow::Result<Vec<ActionResource>> {
        let Self {
            chain_id,
            forwarder,
            token,
            consumed,
            pull,
            main_receiver,
            splits,
            source: _,
        } = self;
        let main_receiver = main_receiver.context("the action consumes no resource")?;
        let (mut resources, total) = match consumed {
            Consumed::Account {
                payer,
                quantity,
                nonce,
            } => {
                anyhow::ensure!(quantity > 0, "the wrap pulls no tokens");
                (
                    vec![ephemeral::consumed(
                        &payer, chain_id, forwarder, token, quantity, nonce, pull,
                    )],
                    quantity,
                )
            }
            Consumed::Resources(inputs) => {
                anyhow::ensure!(!inputs.is_empty(), "the action consumes no resource");
                let label_ref = calculate_label_ref(forwarder.as_ref(), token.as_ref());
                let mut resources = Vec::with_capacity(inputs.len());
                let mut total: u128 = 0;
                for (index, (owner, resource)) in inputs.into_iter().enumerate() {
                    anyhow::ensure!(
                        resource.label_ref == label_ref,
                        "input {index} holds another token or belongs to another forwarder"
                    );
                    total = total.checked_add(resource.quantity).with_context(|| {
                        format!("the inputs up to input {index} hold more than u128::MAX tokens")
                    })?;
                    let path = commitment_path(env, resource.commitment())
                        .with_context(|| format!("input {index} is not in the commitment tree"))?;
                    resources.push(persistent::consumed(&owner, resource, path, None));
                }
                (resources, total)
            }
        };

        let mut rest = total;
        for (index, (_, quantity)) in splits.iter().enumerate() {
            anyhow::ensure!(*quantity > 0, "split {index} gives no tokens");
            rest = rest.checked_sub(*quantity).with_context(|| {
                format!("the splits up to split {index} take more than the {total} tokens")
            })?;
        }
        anyhow::ensure!(
            rest > 0,
            "the splits take all {total} tokens, so the main receiver gets none"
        );

        resources.push(created(main_receiver, forwarder, token, rest));
        for (receiver, quantity) in splits {
            resources.push(created(receiver, forwarder, token, quantity));
        }
        Ok(resources)
    }

    /// The action.
    pub fn build<Env: Environment>(self, env: &Env) -> anyhow::Result<ActionWitnesses> {
        action::build(self.resources(env)?)
    }
}

impl ActionBuilder<FromAccount> {
    /// Pulls the tokens from `account` instead of the payer's account.
    pub fn from_account(mut self, account: Address) -> Self {
        self.pull.ethereum_account_addr = Some(account);
        self
    }

    /// Uses `signature` instead of the payer's Permit2 signature.
    pub fn permit_signature(mut self, signature: Vec<u8>) -> Self {
        self.pull.permit_signature = Some(signature);
        self
    }
}

fn created(
    receiver: Receiver,
    forwarder: Address,
    token: Address,
    quantity: u128,
) -> ActionResource {
    match receiver {
        Receiver::Owner(owner) => persistent::created(&owner, forwarder, token, quantity),
        Receiver::Account(account) => ephemeral::created(account, forwarder, token, quantity),
    }
}
