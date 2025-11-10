use crate::evm::IndexerError::{
    IndexerOverloaded, InvalidIndexerUrl, InvalidResponse, MerklePathNotFound, NeighbourValueError,
    Recoverable, Unrecoverable,
};
use crate::evm::IndexerResult;
use crate::AnomaPayConfig;
use arm::merkle_path::MerklePath;
use arm::Digest;
use log::{error, warn};
use reqwest::{Client, Url};
use serde::Deserialize;
use serde_with::hex::Hex;
use serde_with::serde_as;
use std::time::Duration;
use tokio::time::sleep;

#[serde_as]
#[derive(Deserialize, Debug, PartialEq)]
struct ProofResponse {
    root: String,
    frontiers: Vec<Frontier>,
}

#[serde_as]
#[derive(Deserialize, Debug, PartialEq)]
struct Frontier {
    #[serde_as(as = "Hex")]
    neighbour: Vec<u8>,
    is_left: bool,
}

/// Given a ProofResponse, parses into a MerklePath.
fn parse_merkle_path(proof_response: ProofResponse) -> IndexerResult<MerklePath> {
    let merkle_path: IndexerResult<Vec<(Digest, bool)>> = proof_response
        .frontiers
        .into_iter()
        .map(|frontier| {
            let bytes: [u8; 32] = frontier
                .neighbour
                .as_slice()
                .try_into()
                .map_err(|_| NeighbourValueError(frontier.neighbour))?;
            let sibling_digest = Digest::from(bytes);
            Ok((sibling_digest, !frontier.is_left))
        })
        .collect();

    let merkle_path_vec = merkle_path?;
    Ok(MerklePath::from_path(merkle_path_vec.as_slice()))
}

/// Try to get the merkle path from the indexer for the given commitment.
/// If the path is
async fn get_merkle_path(client: &Client, url: &Url) -> IndexerResult<ProofResponse> {
    // Make the request to the indexer
    let response = client.get(url.to_owned()).send().await;

    // Try parse the result of the indexer
    match response {
        Ok(response) => {
            match response.error_for_status_ref() {
                // got a valid response from the indexer
                Ok(_) => response
                    .json::<ProofResponse>()
                    .await
                    .map_err(|_| InvalidResponse),
                // too many requests is recoverable, but requires waiting a bit longer
                Err(err) if err.status() == Some(reqwest::StatusCode::TOO_MANY_REQUESTS) => {
                    Err(IndexerOverloaded)
                }
                // some errors are recoverable
                Err(err)
                if err.status().is_some_and(|s| s.is_server_error()) // 5xx errors.
                    || err.is_connect() // DNS resolution failures, connection refused/reset, etc.
                    || err.is_timeout() // Request or connect timeout.
                    || err.is_request() // Transient request build/dispatch issue.
                    || err.is_body()    // Transient body read/decode issues.
                =>
                    {
                        Err(Recoverable(err))
                    }
                // any other HTTP response codes are unrecoverable
                Err(err) => {
                    // Non-retryable. Bubble up immediately.
                    Err(Unrecoverable(err))
                }
            }
        }
        // failed to communicate with the webserver (wrong url or something)
        Err(err) => Err(Unrecoverable(err)),
    }
}

/// Tries to fetch the merkle path for the given commitment, and retries at most `retries` times.
async fn try_get_merkle_path(
    client: &Client,
    url: &Url,
    tries: u32,
) -> IndexerResult<ProofResponse> {
    for attempt in 0..=tries {
        let delay = Duration::from_millis(250 * 2_u64.pow(attempt));
        sleep(delay).await;

        let result = get_merkle_path(client, url).await;

        match result {
            Ok(proof_response) => return Ok(proof_response),
            Err(IndexerOverloaded) => {}
            Err(Recoverable(err)) => {
                warn!("recoverable error while getting merkle path: {err:?}")
            }
            Err(Unrecoverable(err)) => {
                error!("unrecoverable error while getting merkle path: {err:?}")
            }
            Err(err) => return Err(err),
        }
        warn!("failed to get merkle path, attempting again...")
    }

    // tried `tries` times and did not get a result
    Err(MerklePathNotFound)
}

/// Given a commitment of a resource, looks up the merkle path for this resource.
pub async fn pa_merkle_path(
    config: &AnomaPayConfig,
    commitment: Digest,
) -> IndexerResult<MerklePath> {
    let url = format!("{}/generate_proof/0x{}", config.indexer_address, commitment)
        .parse()
        .map_err(|_e| InvalidIndexerUrl)?;

    let client = Client::new();

    let indexer_response = try_get_merkle_path(&client, &url, 5).await?;
    parse_merkle_path(indexer_response)
}

#[cfg(test)]
mod tests {
    use crate::evm::indexer::pa_merkle_path;
    use crate::load_config;
    use arm::Digest;

    #[tokio::test]
    async fn fails_with_internal_server_error_on_non_existent_commitment() {
        let config = load_config().expect("failed to load config in test");
        let cm = Digest::new([0u32; 8]);

        let result = pa_merkle_path(&config, cm).await;
        assert!(result.is_err());
    }
}
