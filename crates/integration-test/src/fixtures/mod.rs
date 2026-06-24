//! AnomaPay ERC20 action fixtures, one module per action kind on the
//! token-transfer resource. Each kind exposes the single-builder surface of
//! testkit ADR-0003 — `build`, the derived-data bundle `ActionData`, and
//! `Overrides` with named `invalid_*` variants for negative tests. The shared
//! resource logic (verifying key + witness adapter) lives in [`crate::logic`].

mod resource;

pub mod transfer;
pub mod unwrap;
pub mod wrap;
