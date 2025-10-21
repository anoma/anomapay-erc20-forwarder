/// An error struct to signal an error occurred during the creation of a transaction.
#[derive(Debug)]
pub enum EvmError {
    EvmSubmitError,
    Indexer(IndexerError),
    MerklePathNotFound,
    MerklePathValueError,
}

#[derive(Debug)]
pub enum IndexerError {
    InvalidIndexer,
    Recoverable(reqwest::Error),
    Unrecoverable(reqwest::Error),
    OverloadedIndexer,
}
