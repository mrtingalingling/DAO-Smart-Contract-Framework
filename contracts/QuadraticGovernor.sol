// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "./MemberToken.sol";
import "./ICrsManager.sol";

/**
 * @title QuadraticGovernor
 * @dev Governance module for Stage 2: Resource Allocation (Quadratic Voting).
 * Allocates voting credits based on Contribution Reputation Score (CRS).
 * The voting power gained is the square root of credits spent: V = sqrt(C).
 */
contract QuadraticGovernor is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    struct ProposalVote {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        mapping(address => uint256) spentCredits;
        mapping(address => bool) hasVoted;
    }

    ERC1155TokenUpgradeable public memberToken;
    ICrsManager public crsManager;
    address public governorGeneral;
    uint256 public quadraticQuorum;

    // Base credits multiplier (1e18 score = 10,000 voting credits)
    uint256 public constant CREDITS_SCALE = 1e14;
    uint256 public constant MIN_CREDITS = 1_000;

    mapping(uint256 => ProposalVote) private _proposalVotes;

    event QuadraticVoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 creditsSpent,
        uint256 votesCast
    );
    event QuadraticQuorumUpdated(uint256 oldQuorum, uint256 newQuorum);
    event GovernorGeneralUpdated(address indexed oldGovernorGeneral, address indexed newGovernorGeneral);

    error OnlyGovernorGeneral();
    error AlreadyVoted();
    error NotMember();
    error InvalidVoteChoice();
    error InsufficientVotingCredits();
    error ZeroCreditsSpent();
    error ZeroAddress();

    modifier onlyGovernorGeneral() {
        if (msg.sender != governorGeneral && msg.sender != owner()) {
            revert OnlyGovernorGeneral();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _governorGeneral,
        address _memberToken,
        address _crsManager,
        uint256 _quadraticQuorum
    ) public initializer {
        if (_governorGeneral == address(0) || _memberToken == address(0) || _crsManager == address(0)) {
            revert ZeroAddress();
        }
        __Ownable_init(msg.sender);

        governorGeneral = _governorGeneral;
        memberToken = ERC1155TokenUpgradeable(_memberToken);
        crsManager = ICrsManager(_crsManager);
        quadraticQuorum = _quadraticQuorum;
    }

    function setGovernorGeneral(address _governorGeneral) external onlyOwner {
        if (_governorGeneral == address(0)) revert ZeroAddress();
        emit GovernorGeneralUpdated(governorGeneral, _governorGeneral);
        governorGeneral = _governorGeneral;
    }

    function setQuadraticQuorum(uint256 _quadraticQuorum) external onlyOwner {
        emit QuadraticQuorumUpdated(quadraticQuorum, _quadraticQuorum);
        quadraticQuorum = _quadraticQuorum;
    }

    /**
     * @notice Computes maximum voting credits allocated to a member based on CRS.
     */
    function getCreditBudget(address voter, uint256 tokenId) public view returns (uint256) {
        uint256 score = crsManager.getCrs(voter, tokenId);
        if (score == 0) {
            return MIN_CREDITS;
        }
        uint256 calculated = score / CREDITS_SCALE;
        return calculated > MIN_CREDITS ? calculated : MIN_CREDITS;
    }

    /**
     * @notice Casts a quadratic vote for a proposal in Stage 2.
     * @param proposalId The ID of the proposal.
     * @param voter The address of the voter.
     * @param support 0 = Against, 1 = For, 2 = Abstain.
     * @param creditsToSpend Amount of voting credits to spend (V = sqrt(credits)).
     * @param tokenId The ERC1155 member badge token ID.
     * @param snapshot The snapshot block number for balance check.
     */
    function castVote(
        uint256 proposalId,
        address voter,
        uint8 support,
        uint256 creditsToSpend,
        uint256 tokenId,
        uint256 snapshot
    ) external onlyGovernorGeneral returns (uint256) {
        if (support > 2) revert InvalidVoteChoice();
        if (creditsToSpend == 0) revert ZeroCreditsSpent();

        ProposalVote storage pv = _proposalVotes[proposalId];
        if (pv.hasVoted[voter]) revert AlreadyVoted();

        // Verify membership at snapshot block
        uint256 balance = memberToken.getPastBalanceOf(voter, tokenId, snapshot);
        if (balance == 0) revert NotMember();

        // Verify credit budget
        uint256 maxCredits = getCreditBudget(voter, tokenId);
        if (creditsToSpend > maxCredits) revert InsufficientVotingCredits();

        // Calculate quadratic votes: V = sqrt(C)
        uint256 votesCast = Math.sqrt(creditsToSpend);

        pv.hasVoted[voter] = true;
        pv.spentCredits[voter] = creditsToSpend;

        if (support == 0) {
            pv.againstVotes += votesCast;
        } else if (support == 1) {
            pv.forVotes += votesCast;
        } else {
            pv.abstainVotes += votesCast;
        }

        emit QuadraticVoteCast(voter, proposalId, support, creditsToSpend, votesCast);
        return votesCast;
    }

    function hasVoted(uint256 proposalId, address account) external view returns (bool) {
        return _proposalVotes[proposalId].hasVoted[account];
    }

    function getSpentCredits(uint256 proposalId, address account) external view returns (uint256) {
        return _proposalVotes[proposalId].spentCredits[account];
    }

    function getVotes(uint256 proposalId) external view returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) {
        ProposalVote storage pv = _proposalVotes[proposalId];
        return (pv.forVotes, pv.againstVotes, pv.abstainVotes);
    }

    function hasPassed(uint256 proposalId) external view returns (bool) {
        ProposalVote storage pv = _proposalVotes[proposalId];
        return (pv.forVotes >= quadraticQuorum && pv.forVotes > pv.againstVotes);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[49] private __gap;
}
