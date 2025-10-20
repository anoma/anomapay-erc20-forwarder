use crate::evm::errors::EvmError;
use crate::evm::errors::EvmError::IndexerError;
use alloy::hex::ToHexExt;
use arm::merkle_path::MerklePath;
use arm::Digest;
use futures::TryFutureExt;
use reqwest::{Error, Url};
use serde::Deserialize;
use serde_with::hex::Hex;
use serde_with::serde_as;
use std::time::Duration;

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

/// Fetches the merkle path from the indexer and returns its parsed response. On
/// This still has to be converted into a real MerklePath struct.
async fn merkle_path_from_indexer(commitment: Digest) -> Result<ProofResponse, Error> {
    let hash = ToHexExt::encode_hex(&commitment);
    let url: Url = format!("http://localhost:4000/generate_proof/0x{hash}")
        .parse()
        .unwrap();

    let client = reqwest::Client::new();
    let mut delay = Duration::from_millis(250);
    let mut last_err: Option<Error> = None;

    for attempt in 1..=6 {
        let resp_res = client.get(url.clone()).send().await?;

        match resp_res.error_for_status_ref() {
            Ok(_) => {
                let json = resp_res.json::<ProofResponse>().await?;
                println!("{json:?}");
                return Ok(json);
            }
            Err(err) if err.status() == Some(reqwest::StatusCode::TOO_MANY_REQUESTS) => {
                let dur = Duration::from_secs(10);
                println!("Attempt #{attempt} failed with {err:?}. Retry in {dur:?}...");

                tokio::time::sleep(dur).await;
                last_err = Some(err);
            }
            Err(err)
                if err.status().is_some_and(|s| s.is_server_error()) // 5xx errors.
                    || err.is_connect() // DNS resolution failures, connection refused/reset, etc.
                    || err.is_timeout() // Request or connect timeout.
                    || err.is_request() // Transient request build/dispatch issue.
                    || err.is_body()    // Transient body read/decode issues.
            =>
            {
                println!("Attempt #{attempt} failed with {err:?}. Retry in {delay:?}...");
                tokio::time::sleep(delay).await;

                // Update last error.
                last_err = Some(err);

                // Prepare for the next attempt.
                delay *= 2;
            }
            Err(err) => {
                // Non-retryable. Bubble up immediately.
                return Err(err);
            }
        }
    }
    match last_err {
        Some(e) => Err(reqwest::Error::from(e)),
        None => panic!("exhausted retries without a specific error"),
    }
}

/// Given a commitment of a resource, looks up the merkle path for this resource.
pub async fn pa_merkle_path(commitment: Digest) -> Result<MerklePath, EvmError> {
    let merkle_path_response = merkle_path_from_indexer(commitment)
        .map_err(|_| IndexerError)
        .await?;

    let x: Result<Vec<(Digest, bool)>, EvmError> = merkle_path_response
        .frontiers
        .into_iter()
        .map(|frontier| {
            let bytes: [u8; 32] = frontier
                .neighbour
                .as_slice()
                .try_into()
                .map_err(|_| IndexerError)?;
            println!("{:?}", bytes);
            let sibling_digest = Digest::from(bytes);
            Ok((sibling_digest, !frontier.is_left))
        })
        .collect();

    let merkle_path_vec = x?;

    Ok(MerklePath::from_path(merkle_path_vec.as_slice()))
}

#[cfg(test)]
mod tests {
    use crate::evm::indexer::merkle_path_from_indexer;
    use arm::Digest;

    #[tokio::test]
    async fn fails_with_internal_server_error_on_non_existent_commitment() {
        let cm = Digest::new([0u32; 8]);
        assert_eq!(
            merkle_path_from_indexer(cm)
                .await
                .err()
                .unwrap()
                .status()
                .unwrap(),
            reqwest::StatusCode::INTERNAL_SERVER_ERROR
        );
    }
}
