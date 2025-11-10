use thiserror::Error;

pub mod approve;
pub mod burn;
pub mod mint;
pub mod resource;
pub mod split;
pub mod transfer;

pub type DecodeResult<T> = Result<T, DecodingErr>;

#[derive(Debug, Error)]
pub enum DecodingErr {
    #[error("Resource contains invalid resource nullifier key commitment.")]
    ResourceInvalidNullifierKeyCommitment,
    #[error("Error computing nullifier of the consumed resource.")]
    InvalidNullifierKey,
    #[error("Error decoding field to digest ({0}")]
    DigestDecodingError(String),
    #[error("Error decoding field to array ({0}")]
    ArrayDecodingError(String),
    #[error("Error decoding AuthorizationSignature field ({0})")]
    AuthorizationSignatureDecodeError(String),
    #[error("Error decoding latest commitment tree root field ({0})")]
    LatestCommitmentTreeRootDecodeError(String),
}

pub type RequestResult<T> = Result<T, RequestErr>;
#[derive(Error, Debug)]
pub enum RequestErr {
    #[error("Error handling mint request {0}")]
    FailedMintRequest(Box<dyn std::error::Error>),
    #[error("Error handling burn request {0}")]
    FailedBurnRequest(Box<dyn std::error::Error>),
    #[error("Error handling split request {0}")]
    FailedSplitRequest(Box<dyn std::error::Error>),
    #[error("Error handling transfer request {0}")]
    FailedTransferRequest(Box<dyn std::error::Error>),
}
/// This trait converts from the simplified structs into their full equivalent.
/// For example, RequestResource to Resource.
pub trait Expand {
    type Struct;
    type Error;

    fn simplify(&self) -> Self::Struct;
    fn expand(json: Self::Struct) -> DecodeResult<Self>
    where
        Self: Sized;
}

fn to_array<const N: usize>(v: Vec<u8>, field: &str) -> Result<[u8; N], String> {
    v.try_into().map_err(|_| format!("{field} invalid size"))
}
