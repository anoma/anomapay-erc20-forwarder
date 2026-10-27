//! AnomaPay ERC20 action kinds, one module per action kind on the ERC20 resource. Each kind exposes
//! `resources`, which gives its action resources for
//! [`anoma_pa_testkit::fixtures::action::build`], and `Overrides` with named `invalid_*` variants for
//! negative tests. The shared resource logic lives in [`crate::logic`].

mod resource;

pub mod transfer;
pub mod unwrap;
pub mod wrap;
