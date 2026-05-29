//! Unwrap action: withdraws ERC20 tokens from the forwarder, consuming a
//! persistent wrapped resource (authorized by a signature) and creating an
//! ephemeral resource that releases the tokens to an Ethereum account.

mod action;
mod resource;

pub use action::{ActionData, build};
pub use resource::Overrides;
