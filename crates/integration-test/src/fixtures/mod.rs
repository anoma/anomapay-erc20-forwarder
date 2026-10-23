//! AnomaPay ERC20 action fixtures, one module per action kind on the
//! token-transfer resource. Each kind exposes `build`, which builds an action
//! of the kind, the derived-data bundle `ActionData`, `Overrides` with named
//! `invalid_*` variants for negative tests, and `parts`, its resources for an
//! action that [`action::build`] assembles from several kinds. The shared
//! resource logic (verifying key + witness adapter) lives in [`crate::logic`].

mod resource;

pub mod action;
pub mod transfer;
pub mod unwrap;
pub mod wrap;
