use reqwest::Client;
use serde::{Deserialize, Serialize};

use crate::web::RequestError;

#[derive(Serialize, Deserialize)]
pub struct QueueStatsInfo {
    pub created_requests: usize,
    pub pending_requests: usize,
    pub completed_requests: usize,
}

pub async fn get_queue_stats(queue_base_url: &str) -> Result<QueueStatsInfo, RequestError> {
    let client = Client::new();
    let url = format!("{}/api/v1/stats", queue_base_url);

    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|_e| RequestError::NetworkError(url.clone()))?;

    let stats: QueueStatsInfo = resp
        .json()
        .await
        .map_err(|_e| RequestError::NetworkError(url.clone()))?;

    Ok(stats)
}
