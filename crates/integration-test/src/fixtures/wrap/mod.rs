//! Wrap action: deposits ERC20 tokens into the forwarder, consuming an
//! ephemeral resource (authorized by a Permit2 signature) and creating a
//! persistent wrapped resource.

mod action;
mod resource;

pub use action::{ActionData, build};
pub use resource::Overrides;
