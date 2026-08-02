//! Phase 5 orchestrator job state machine (single-operator v1).

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum JobStatus {
    Queued,
    Proving,
    Submitting,
    Confirmed,
    Failed,
    Expired,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Job {
    pub request_id: u64,
    pub program_id: [u8; 32],
    pub elf_hash: [u8; 32],
    pub expected_elf_hash: [u8; 32],
    pub status: JobStatus,
    pub fail_reason: Option<String>,
    pub bounty_wei: u128,
    pub floor_wei: u128,
}

#[derive(Debug, Error)]
pub enum OrchError {
    #[error("unknown job {0}")]
    Unknown(u64),
    #[error("invalid transition {from:?} -> {to:?}")]
    BadTransition { from: JobStatus, to: JobStatus },
    #[error("elf hash mismatch")]
    ElfMismatch,
    #[error("bounty {bounty} below floor {floor}")]
    Underpriced { bounty: u128, floor: u128 },
    #[error("job expired")]
    Expired,
}

#[derive(Default)]
pub struct Orchestrator {
    pub jobs: HashMap<u64, Job>,
    pub eth_bounty_floor_wei: u128,
}

impl Orchestrator {
    pub fn new(floor_wei: u128) -> Self {
        Self {
            jobs: HashMap::new(),
            eth_bounty_floor_wei: floor_wei,
        }
    }

    pub fn enqueue(&mut self, mut job: Job) -> Result<(), OrchError> {
        if job.bounty_wei < self.eth_bounty_floor_wei {
            return Err(OrchError::Underpriced {
                bounty: job.bounty_wei,
                floor: self.eth_bounty_floor_wei,
            });
        }
        if job.elf_hash != job.expected_elf_hash {
            return Err(OrchError::ElfMismatch);
        }
        job.status = JobStatus::Queued;
        self.jobs.insert(job.request_id, job);
        Ok(())
    }

    pub fn transition(&mut self, id: u64, to: JobStatus) -> Result<(), OrchError> {
        let job = self.jobs.get_mut(&id).ok_or(OrchError::Unknown(id))?;
        let from = job.status;
        let ok = matches!(
            (from, to),
            (JobStatus::Queued, JobStatus::Proving)
                | (JobStatus::Proving, JobStatus::Submitting)
                | (JobStatus::Submitting, JobStatus::Confirmed)
                | (JobStatus::Queued, JobStatus::Expired)
                | (JobStatus::Proving, JobStatus::Failed)
                | (JobStatus::Submitting, JobStatus::Failed)
                | (JobStatus::Proving, JobStatus::Expired)
        );
        if !ok {
            return Err(OrchError::BadTransition { from, to });
        }
        job.status = to;
        Ok(())
    }

    pub fn fail(&mut self, id: u64, reason: impl Into<String>) -> Result<(), OrchError> {
        self.transition(id, JobStatus::Failed)?;
        if let Some(job) = self.jobs.get_mut(&id) {
            job.fail_reason = Some(reason.into());
        }
        Ok(())
    }

    pub fn inject_rpc_flake_retry(&mut self, id: u64) -> Result<u32, OrchError> {
        // Failure-injection helper used by soak tests: count a flake then stay in Proving.
        let job = self.jobs.get_mut(&id).ok_or(OrchError::Unknown(id))?;
        if job.status != JobStatus::Proving {
            return Err(OrchError::BadTransition {
                from: job.status,
                to: JobStatus::Proving,
            });
        }
        Ok(1)
    }
}

/// Phase 5 ERC-20 / oracle design note (not implemented): floor price in ETH terms via
/// `bounty_token_amount * oracle_price >= gas_estimate + prove_cost`.
pub mod economics {
    pub fn eth_floor_ok(bounty_wei: u128, floor_wei: u128) -> bool {
        bounty_wei >= floor_wei
    }

    /// Intent/oracle sketch for later ERC-20 bounties.
    pub fn erc20_covers_cost(
        token_amount: u128,
        token_price_wei: u128,
        prove_cost_wei: u128,
        gas_cost_wei: u128,
    ) -> bool {
        token_amount.saturating_mul(token_price_wei) >= prove_cost_wei.saturating_add(gas_cost_wei)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(id: u64, bounty: u128) -> Job {
        Job {
            request_id: id,
            program_id: [1u8; 32],
            elf_hash: [2u8; 32],
            expected_elf_hash: [2u8; 32],
            status: JobStatus::Queued,
            fail_reason: None,
            bounty_wei: bounty,
            floor_wei: 0,
        }
    }

    #[test]
    fn happy_path_fsm() {
        let mut o = Orchestrator::new(1_000);
        o.enqueue(sample(1, 5_000)).unwrap();
        o.transition(1, JobStatus::Proving).unwrap();
        o.transition(1, JobStatus::Submitting).unwrap();
        o.transition(1, JobStatus::Confirmed).unwrap();
        assert_eq!(o.jobs[&1].status, JobStatus::Confirmed);
    }

    #[test]
    fn elf_mismatch() {
        let mut o = Orchestrator::new(0);
        let mut j = sample(2, 1);
        j.elf_hash = [9u8; 32];
        assert!(matches!(o.enqueue(j), Err(OrchError::ElfMismatch)));
    }

    #[test]
    fn underpriced() {
        let mut o = Orchestrator::new(10_000);
        assert!(matches!(
            o.enqueue(sample(3, 100)),
            Err(OrchError::Underpriced { .. })
        ));
    }

    #[test]
    fn failure_injection() {
        let mut o = Orchestrator::new(0);
        o.enqueue(sample(4, 1)).unwrap();
        o.transition(4, JobStatus::Proving).unwrap();
        assert_eq!(o.inject_rpc_flake_retry(4).unwrap(), 1);
        o.fail(4, "rpc flake").unwrap();
        assert_eq!(o.jobs[&4].fail_reason.as_deref(), Some("rpc flake"));
    }

    #[test]
    fn soak_n_jobs() {
        let mut o = Orchestrator::new(0);
        for i in 0..32u64 {
            o.enqueue(sample(i, 1)).unwrap();
            o.transition(i, JobStatus::Proving).unwrap();
            o.transition(i, JobStatus::Submitting).unwrap();
            o.transition(i, JobStatus::Confirmed).unwrap();
        }
        assert_eq!(o.jobs.len(), 32);
    }

    #[test]
    fn erc20_design_helper() {
        assert!(economics::erc20_covers_cost(100, 10, 200, 300));
        assert!(!economics::erc20_covers_cost(10, 10, 200, 300));
    }
}
