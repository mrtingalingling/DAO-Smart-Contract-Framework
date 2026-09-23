// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./MemberToken.sol";
import "./ApprovalGovernor.sol";
import "./QuadraticGovernor.sol";

/**
 * @title GovernorGeneral
 * @dev The Core contract of the DAO framework.
 * Orchestrates multi-stage governance proposals across Approval (Stage 1)
 * and Quadratic (Stage 2) voting modules, interfacing directly with the Timelock.
 */
contract GovernorGeneral is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    enum ProposalStage {
        Pending,
        Approval,
        Quadratic,
        Succeeded,
        Queued,
        Executed,
        Defeated,
        Canceled
    }

    struct Proposal {
        address proposer;
        ProposalStage stage;
        uint48 voteStart;
        uint48 approvalEnd;
        uint48 quadraticStart;
        uint48 quadraticEnd;
        bool exists;
        bool canceled;
        bool executed;
    }

    ERC1155TokenUpgradeable public memberToken;
    ApprovalGovernor public approvalGovernor;
    QuadraticGovernor public quadraticGovernor;
    TimelockControllerUpgradeable public timelock;

    uint32 public votingDelay;
    uint32 public approvalPeriod;
    uint32 public quadraticPeriod;
    uint256 public proposalThreshold;
    uint256 public defaultMemberTokenId;

    mapping(uint256 => Proposal) public proposals;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint48 voteStart,
        uint48 approvalEnd,
        string description
    );
    event ProposalStageAdvanced(uint256 indexed proposalId, ProposalStage newStage);
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);

    error ProposalAlreadyExists();
    error ProposalDoesNotExist();
    error InsufficientProposerVotes();
    error InvalidProposalStage(ProposalStage expected, ProposalStage actual);
    error VotingNotActive();
    error StageCriteriaNotMet();
    error OnlyProposerOrTimelock();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _memberToken,
        address _approvalGovernor,
        address _quadraticGovernor,
        address payable _timelock,
        uint32 _votingDelay,
        uint32 _approvalPeriod,
        uint32 _quadraticPeriod,
        uint256 _proposalThreshold,
        uint256 _defaultMemberTokenId
    ) public initializer {
        __Ownable_init(msg.sender);

        memberToken = ERC1155TokenUpgradeable(_memberToken);
        approvalGovernor = ApprovalGovernor(_approvalGovernor);
        quadraticGovernor = QuadraticGovernor(_quadraticGovernor);
        timelock = TimelockControllerUpgradeable(_timelock);

        votingDelay = _votingDelay;
        approvalPeriod = _approvalPeriod;
        quadraticPeriod = _quadraticPeriod;
        proposalThreshold = _proposalThreshold;
        defaultMemberTokenId = _defaultMemberTokenId;
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    /**
     * @notice Creates a new proposal entering Stage 1 (Approval).
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        // Enforce proposal threshold
        uint256 currentBlock = block.number;
        uint256 pastBlock = currentBlock > 0 ? currentBlock - 1 : 0;
        uint256 proposerBalance = memberToken.getPastBalanceOf(msg.sender, defaultMemberTokenId, pastBlock);
        if (proposerBalance < proposalThreshold) {
            revert InsufficientProposerVotes();
        }

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        if (proposals[proposalId].exists) revert ProposalAlreadyExists();

        uint48 start = SafeCast.toUint48(currentBlock + votingDelay);
        uint48 end = SafeCast.toUint48(start + approvalPeriod);

        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            stage: ProposalStage.Approval,
            voteStart: start,
            approvalEnd: end,
            quadraticStart: 0,
            quadraticEnd: 0,
            exists: true,
            canceled: false,
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, targets, values, calldatas, start, end, description);
        return proposalId;
    }

    /**
     * @notice Casts an Approval vote during Stage 1.
     */
    function castApprovalVote(
        uint256 proposalId,
        uint8 support,
        uint256 tokenId
    ) public returns (uint256) {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (state(proposalId) != ProposalStage.Approval) {
            revert InvalidProposalStage(ProposalStage.Approval, state(proposalId));
        }

        return approvalGovernor.castVote(proposalId, msg.sender, support, tokenId, p.voteStart);
    }

    /**
     * @notice Permissionlessly advances proposal from Approval to Quadratic stage if passed.
     */
    function advanceToQuadratic(uint256 proposalId) public {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (block.number <= p.approvalEnd) revert VotingNotActive();
        if (p.stage != ProposalStage.Approval) {
            revert InvalidProposalStage(ProposalStage.Approval, p.stage);
        }

        if (approvalGovernor.hasPassed(proposalId)) {
            p.stage = ProposalStage.Quadratic;
            p.quadraticStart = SafeCast.toUint48(block.number);
            p.quadraticEnd = SafeCast.toUint48(block.number + quadraticPeriod);
            emit ProposalStageAdvanced(proposalId, ProposalStage.Quadratic);
        } else {
            p.stage = ProposalStage.Defeated;
            emit ProposalStageAdvanced(proposalId, ProposalStage.Defeated);
        }
    }

    /**
     * @notice Casts a Quadratic vote during Stage 2.
     */
    function castQuadraticVote(
        uint256 proposalId,
        uint8 support,
        uint256 creditsToSpend,
        uint256 tokenId
    ) public returns (uint256) {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (state(proposalId) != ProposalStage.Quadratic) {
            revert InvalidProposalStage(ProposalStage.Quadratic, state(proposalId));
        }

        return quadraticGovernor.castVote(
            proposalId,
            msg.sender,
            support,
            creditsToSpend,
            tokenId,
            p.quadraticStart
        );
    }

    /**
     * @notice Finalizes quadratic voting stage.
     */
    function finalizeQuadratic(uint256 proposalId) public {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (p.stage != ProposalStage.Quadratic) {
            revert InvalidProposalStage(ProposalStage.Quadratic, p.stage);
        }
        if (block.number <= p.quadraticEnd) revert VotingNotActive();

        if (quadraticGovernor.hasPassed(proposalId)) {
            p.stage = ProposalStage.Succeeded;
            emit ProposalStageAdvanced(proposalId, ProposalStage.Succeeded);
        } else {
            p.stage = ProposalStage.Defeated;
            emit ProposalStageAdvanced(proposalId, ProposalStage.Defeated);
        }
    }

    /**
     * @notice Queues a succeeded proposal into the Timelock.
     */
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();

        // Auto-finalize if stage is still Quadratic but deadline elapsed
        if (p.stage == ProposalStage.Quadratic && block.number > p.quadraticEnd) {
            finalizeQuadratic(proposalId);
        }

        if (p.stage != ProposalStage.Succeeded) {
            revert InvalidProposalStage(ProposalStage.Succeeded, p.stage);
        }

        uint256 delay = timelock.getMinDelay();
        timelock.scheduleBatch(targets, values, calldatas, 0, descriptionHash, delay);

        p.stage = ProposalStage.Queued;
        emit ProposalQueued(proposalId, block.timestamp + delay);
        return proposalId;
    }

    /**
     * @notice Executes a queued proposal from the Timelock.
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (p.stage != ProposalStage.Queued) {
            revert InvalidProposalStage(ProposalStage.Queued, p.stage);
        }

        p.executed = true;
        p.stage = ProposalStage.Executed;

        timelock.executeBatch{value: msg.value}(targets, values, calldatas, 0, descriptionHash);
        emit ProposalExecuted(proposalId);
        return proposalId;
    }

    /**
     * @notice Cancels a proposal before execution.
     */
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (msg.sender != p.proposer && msg.sender != owner() && msg.sender != address(timelock)) {
            revert OnlyProposerOrTimelock();
        }
        if (p.executed || p.stage == ProposalStage.Executed) revert StageCriteriaNotMet();

        p.canceled = true;
        p.stage = ProposalStage.Canceled;

        // If queued in timelock, cancel timelock operations
        bytes32 id = timelock.hashOperationBatch(targets, values, calldatas, 0, descriptionHash);
        if (timelock.isOperation(id)) {
            timelock.cancel(id);
        }

        emit ProposalCanceled(proposalId);
        return proposalId;
    }

    /**
     * @notice Current lifecycle state of a proposal.
     */
    function state(uint256 proposalId) public view returns (ProposalStage) {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert ProposalDoesNotExist();
        if (p.canceled) return ProposalStage.Canceled;
        if (p.executed) return ProposalStage.Executed;

        if (p.stage == ProposalStage.Approval) {
            if (block.number < p.voteStart) {
                return ProposalStage.Pending;
            } else if (block.number <= p.approvalEnd) {
                return ProposalStage.Approval;
            } else {
                return approvalGovernor.hasPassed(proposalId) ? ProposalStage.Approval : ProposalStage.Defeated;
            }
        }

        if (p.stage == ProposalStage.Quadratic) {
            if (block.number <= p.quadraticEnd) {
                return ProposalStage.Quadratic;
            } else {
                return quadraticGovernor.hasPassed(proposalId) ? ProposalStage.Succeeded : ProposalStage.Defeated;
            }
        }

        return p.stage;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[43] private __gap;
}
