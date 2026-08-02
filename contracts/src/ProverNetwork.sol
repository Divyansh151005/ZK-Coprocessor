// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Centralized open-prover registry for Anvil / single-operator orchestration.
/// @dev Not an EigenLayer AVS. Stake → assign → earn / slash for multi-fulfiller demos.
///      EigenLayer AVS integration is deferred (NOTES/PHASE7_L2_MATRIX.md).
contract ProverNetwork {
    struct Prover {
        uint256 stake;
        bool active;
        uint256 slashed;
        uint256 earned;
        bool listed;
    }

    struct Job {
        address assignee;
        bool open;
        uint256 bounty;
    }

    mapping(address => Prover) public provers;
    mapping(uint256 => Job) public jobs;
    address[] public proverList;

    uint256 public minStake;
    address public owner;
    /// @notice Orchestrator address allowed to assign/complete jobs (owner always can).
    address public assigner;

    event ProverJoined(address indexed prover, uint256 stake);
    event ProverSlashed(address indexed prover, uint256 amount, string reason);
    event BountyEarned(address indexed prover, uint256 amount);
    event JobAssigned(uint256 indexed requestId, address indexed prover, uint256 bounty);
    event JobCompleted(uint256 indexed requestId, address indexed prover, uint256 bounty);
    event AssignerUpdated(address indexed assigner);

    error InsufficientStake();
    error NotActive();
    error NotOwner();
    error NotAssigner();
    error AlreadyAssigned();
    error UnknownJob();
    error JobNotOpen();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAssigner() {
        if (msg.sender != assigner && msg.sender != owner) revert NotAssigner();
        _;
    }

    constructor(uint256 minStake_) {
        minStake = minStake_;
        owner = msg.sender;
        assigner = msg.sender;
    }

    function setAssigner(address assigner_) external onlyOwner {
        assigner = assigner_;
        emit AssignerUpdated(assigner_);
    }

    function join() external payable {
        if (msg.value < minStake) revert InsufficientStake();
        Prover storage p = provers[msg.sender];
        if (!p.listed) {
            p.listed = true;
            proverList.push(msg.sender);
        }
        p.stake += msg.value;
        p.active = true;
        emit ProverJoined(msg.sender, p.stake);
    }

    /// @notice Assign an open request to an eligible staked prover.
    function assignJob(uint256 requestId, address prover, uint256 bounty) external onlyAssigner {
        if (!isEligible(prover)) revert NotActive();
        Job storage j = jobs[requestId];
        if (j.open || j.assignee != address(0)) revert AlreadyAssigned();
        j.assignee = prover;
        j.open = true;
        j.bounty = bounty;
        emit JobAssigned(requestId, prover, bounty);
    }

    /// @notice Mark fulfillment complete and credit bounty accounting (ETH settles elsewhere).
    function completeJob(uint256 requestId) external onlyAssigner {
        Job storage j = jobs[requestId];
        if (j.assignee == address(0)) revert UnknownJob();
        if (!j.open) revert JobNotOpen();
        address prover = j.assignee;
        Prover storage p = provers[prover];
        if (!p.active) revert NotActive();
        j.open = false;
        p.earned += j.bounty;
        emit JobCompleted(requestId, prover, j.bounty);
        emit BountyEarned(prover, j.bounty);
    }

    function slash(address prover, uint256 amount, string calldata reason) public onlyOwner {
        Prover storage p = provers[prover];
        if (!p.active) revert NotActive();
        uint256 take = amount > p.stake ? p.stake : amount;
        p.stake -= take;
        p.slashed += take;
        if (p.stake < minStake) p.active = false;
        emit ProverSlashed(prover, take, reason);
    }

    /// @notice Slash assignee for an open job (missed deadline) and close the job.
    function slashMissedJob(uint256 requestId, uint256 amount, string calldata reason) external onlyOwner {
        Job storage j = jobs[requestId];
        if (j.assignee == address(0)) revert UnknownJob();
        if (!j.open) revert JobNotOpen();
        j.open = false;
        slash(j.assignee, amount, reason);
    }

    function recordEarn(address prover, uint256 amount) external onlyOwner {
        Prover storage p = provers[prover];
        if (!p.active) revert NotActive();
        p.earned += amount;
        emit BountyEarned(prover, amount);
    }

    function isEligible(address prover) public view returns (bool) {
        Prover storage p = provers[prover];
        return p.active && p.stake >= minStake;
    }

    function proverCount() external view returns (uint256) {
        return proverList.length;
    }

    /// @notice Round-robin helper: next eligible prover at or after `start` (mod list length).
    function nextEligible(uint256 start) external view returns (address prover, uint256 index) {
        uint256 n = proverList.length;
        if (n == 0) return (address(0), 0);
        for (uint256 i = 0; i < n; i++) {
            uint256 idx = (start + i) % n;
            address cand = proverList[idx];
            if (isEligible(cand)) return (cand, idx);
        }
        return (address(0), 0);
    }
}
