// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Phase 7 open-prover registry (stake/slash sketch; ETH stake for testnet).
contract ProverNetwork {
    struct Prover {
        uint256 stake;
        bool active;
        uint256 slashed;
        uint256 earned;
    }

    mapping(address => Prover) public provers;
    uint256 public minStake;
    address public owner;

    event ProverJoined(address indexed prover, uint256 stake);
    event ProverSlashed(address indexed prover, uint256 amount, string reason);
    event BountyEarned(address indexed prover, uint256 amount);

    error InsufficientStake();
    error NotActive();
    error NotOwner();

    constructor(uint256 minStake_) {
        minStake = minStake_;
        owner = msg.sender;
    }

    function join() external payable {
        if (msg.value < minStake) revert InsufficientStake();
        Prover storage p = provers[msg.sender];
        p.stake += msg.value;
        p.active = true;
        emit ProverJoined(msg.sender, p.stake);
    }

    function slash(address prover, uint256 amount, string calldata reason) external {
        if (msg.sender != owner) revert NotOwner();
        Prover storage p = provers[prover];
        if (!p.active) revert NotActive();
        uint256 take = amount > p.stake ? p.stake : amount;
        p.stake -= take;
        p.slashed += take;
        if (p.stake < minStake) p.active = false;
        emit ProverSlashed(prover, take, reason);
    }

    function recordEarn(address prover, uint256 amount) external {
        if (msg.sender != owner) revert NotOwner();
        Prover storage p = provers[prover];
        if (!p.active) revert NotActive();
        p.earned += amount;
        emit BountyEarned(prover, amount);
    }

    function isEligible(address prover) external view returns (bool) {
        Prover storage p = provers[prover];
        return p.active && p.stake >= minStake;
    }
}
