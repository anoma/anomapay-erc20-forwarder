use alloy::transports::{RpcError, TransportErrorKind};
use alloy_chains::NamedChain;
use thiserror::Error;

pub type BindingsResult<T> = Result<T, BindingsError>;

#[derive(Error, Debug)]
pub enum BindingsError {
    #[error("The chain ID returned by the RPC transport is not in the list of named chains.")]
    ChainIdUnknown,
    #[error("The RPC transport returned an error.")]
    RpcTransportError(RpcError<TransportErrorKind>),
    #[error("The deployment record of the environment has no ERC20 forwarder on the chain '{0}'.")]
    UnsupportedChain(NamedChain),
}
