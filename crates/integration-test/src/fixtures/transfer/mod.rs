//! Transfer action: moves a persistent wrapped resource from one identity to
//! another, consuming the sender's resource (authorized by a signature) and
//! creating a persistent resource owned by the receiver.

mod action;
mod resource;

pub use action::{ActionData, build};
pub use resource::Overrides;
