//! The AnomaPay ERC20 resources, which a test lists in the order of the forwarder calls for
//! [`anoma_pa_testkit::fixtures::action::build`]:
//!
//! - A wrap consumes [`ephemeral`] resources, which pull the tokens, and creates [`persistent`]
//!   resources, which hold them.
//! - A transfer consumes and creates [`persistent`] resources. A split creates more resources than
//!   it consumes, and a merge consumes more resources than it creates.
//! - An unwrap consumes [`persistent`] resources and creates [`ephemeral`] resources, which release
//!   the tokens.
//!
//! In each transaction, the consumed and the created resources of a token hold the same quantity.

pub mod ephemeral;
pub mod persistent;
