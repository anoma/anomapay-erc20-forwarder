//! Integration-test harness for the AnomaPay ERC20 forwarder.
//!
//! Exposes provisioning helpers (`deploy`, `state`), the app's resource `logic`
//! (verifying key and the witness of a consumed persistent resource), and the
//! persistent and ephemeral resources in `fixtures`, from which the scenarios — and
//! dependent apps — build wraps, transfers and unwraps. The scenarios themselves
//! live under `tests/`.

pub mod deploy;
pub mod fixtures;
pub mod logic;
pub mod state;

pub(crate) mod permit2;
