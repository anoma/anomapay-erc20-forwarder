//! Integration-test harness for the AnomaPay ERC20 forwarder.
//!
//! Exposes provisioning helpers (`deploy`, `state`), the app's resource `logic`
//! (verifying key + witness adapter), and the wrap / transfer / unwrap action
//! `fixtures` that the scenarios — and dependent apps — reuse. The scenarios
//! themselves live under `tests/`.

pub mod deploy;
pub mod fixtures;
pub mod logic;
pub mod state;

pub(crate) mod permit2;
