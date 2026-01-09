use reqwest::Client;
use serde::{Deserialize, Serialize};

use crate::web::RequestError;

#[derive(Serialize, Deserialize)]
pub struct QueueStatsInfo {
    pub tasks_created_total: usize,
    pub tasks_completed_total: usize,
    pub tasks_processing_currently: usize,
    pub tasks_error: usize,
}

pub async fn get_queue_stats(queue_base_url: &str) -> Result<QueueStatsInfo, RequestError> {
    let client = Client::new();
    let url = format!("{}/api/v1/stats", queue_base_url);

    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| RequestError::NetworkError(e.to_string()))?;

    let stats: QueueStatsInfo = resp
        .json()
        .await
        .map_err(|e| RequestError::NetworkError(e.to_string()))?;

    Ok(stats)
}
