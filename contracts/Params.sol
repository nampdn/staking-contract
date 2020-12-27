pragma solidity ^0.5.0;
import {Ownable} from "./Ownable.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {SafeMath} from "./Safemath.sol";
import {IParams} from "./interfaces/IParams.sol";


contract Params is Ownable {

    enum ProposalStatus {
        Passed,
        Rejected
    }

    enum VoteOption {
        Yes,
        No,
        Abstain,
    }

    enum ParamKey {
        // staking params
        baseProposerReward,
        bonusProposerReward,
        maxProposers,
        downtimeJailDuration,

        // validator params 
        downtimeJailDuration,
        slashFractionDowntime,
        unbondingTime,
        slashFractionDoubleSign,
        signedBlockWindow,
        minSignedPerWindow,
        minStake,
        minValidatorStake,
        minAmountChangeName,
        minSelfDelegation,

        // minter params
        inflationRateChange,
        goalBonded,
        blocksPerYear,
        inflationMax,
        inflationMin,

        // Proposal
        Deposit,
        VotingPeriod
    }

    using SafeMath for uint256;

    struct Proposal {
        address payable proposer;
        ParamKey[] key;
        uint256[] values;
        uint256 startTime;
        uint256 endTime;
        mapping(address => VoteOption) votes;
        uint256 deposit;
        ProposalStatus status;
        mapping (VoteOption=>uint256) results;
    }

    IStaking private _staking;
    mapping(ParamKey > uint256) public params;
    Proposal[] public proposals;


    constructor() public {
        _staking = IStaking(msg.sender);

        // staking params
        params[ParamKey.baseProposerReward] = 1 * 10**16;
        params[ParamKey.bonusProposerReward] = 4 * 10**16;
        params[ParamKey.maxProposers] = 20;

        // validator params 
        params[ParamKey.downtimeJailDuration] = 300;
        params[ParamKey.slashFractionDowntime] = 5 * 10**16;
        params[ParamKey.unbondingTime] = 300;
        params[ParamKey.slashFractionDoubleSign] = 25 * 10**16;
        params[ParamKey.signedBlockWindow] = 100;
        params[ParamKey.minSignedPerWindow] = 50 * 10**16;
        params[ParamKey.minStake] = 1 * 10**16;
        params[ParamKey.minValidatorStake] = 1 * 10**17;
        params[ParamKey.minAmountChangeName] = 1 *10**17;
        params[ParamKey.minSelfDelegation] = 1 * 10**17;

        // minter
        params[ParamKey.inflationRateChange] =  1 * 10**16;
        params[ParamKey.goalBonded] =  50 * 10**16;
        params[ParamKey.blocksPerYear] =  6307200;
        params[ParamKey.inflationMax] = 5 * 10**16;
        params[ParamKey.inflationMin] = 1 * 10**16;

        params[ParamKey.Deposit] = 1 * 10**17;
        params[ParamKey.VotingPeriod] =  604800 // 7 days
    }

    function addProposal(ParamKey[] memory keys, uint256[] memory values) public payable returns uint {
        require(msg.value >= params[ParamKey.Deposit], "min deposit")
        proposals.push(Proposal({
            keys: keys, 
            values: values,
            proposer: msg.sender,
            deposit: msg.value,
            startTime: block.timestamp,
            endTime: block.timestamp.add(params[ParamKey.VotingPeriod])
        }))
    }

    function addVote(uint proposalId, VoteOption option) public {
        require(proposals.length < proposalId, "proposal not found");
        require(proposals[proposalId].endTime > block.timestamp, "inactive proposal");
        proposals[proposalId].votes[msg.sender] = option;
    }

    function confirmProposal(uint proposalId) public {
        require(proposals.length < proposalId, "proposal not found");
        require(proposals[proposalId].endTime < block.timestamp, "end time");
        address[] memory signers;
        uint256[] memory votingPowers;
        (signers, votingPowers) = staking.getValidatorSets();

        Proposal storage proposal = proposals[proposalId];
        uint256 totalVotingPowers;
        uint256 totalPowerVoteYes;
        uint256 totalPowerVoteNo;
        uint256 totalPowerVoteAbsent;
        for (uint i = 0; i < signers.length; i ++) {
            totalVotingPowers = totalVotingPowers.add(votingPowers[i])
            VoteOption voteOption = proposal.votes[signers[i]];
            if (voteOption == VoteOption.Yes) {
                totalPowerVoteYes = totalPowerVoteYes.add(votingPowers[i]);
            } else if (voteOption == VoteOption.No) {
                totalPowerVoteNo = totalPowerVoteNo.add(votingPowers[i]);
            } else {
                totalPowerVoteAbsent = totalPowerVoteAbsent.add(votingPowers[i]);
            }
        }
        // update result
        proposal.results[VoteOption.Yes] = totalPowerVoteYes;
        proposal.results[VoteOption.No] = totalPowerVoteNo;
        proposal.results[VoteOption.Abstain] = totalPowerVoteAbsent;

        uint256 quorum = totalVotingPowers.mul(2).div(3).add(1)
        if totalPowerVoteYes < quorum {
            proposal.status = ProposalStatus.Rejected;
            // burn deposit token here
            return
        }

        // update params
        for (uint = 0; i < proposal.keys.length; i ++) {
            params[proposal.keys[i]] = proposal.values[i];
        }
        // refund deposit
        proposal.proposer.transfer(proposals[proposalId].deposit);
        proposal.status = ProposalStatus.Passed;
    }


    function getBaseProposerReward() external view returns (uint256) {
        return params[ParamKey.baseProposerReward];
    }

    function getBonusProposerReward() external view returns (uint256) {
        return params[ParamKey.bonusProposerReward];
    }

    function getMaxProposers() external view returns (uint256) {
        return params[ParamKey.maxProposers];
    }

    function getInflationRateChange() external view returns (uint256) {
        return params[ParamKey.inflationRateChange];
    }

    function getGoalBonded() external view returns (uint256) {
        return params[ParamKey.goalBonded];
    }

    function getBlocksPerYear() external view returns (uint256) {
        return params[ParamKey.blocksPerYear];
    }

    function getInflationMax() external view returns (uint256) {
        return params[ParamKey.inflationMax];
    }

    function getInflationMin() external view returns (uint256) {
        return params[ParamKey.inflationMin];
    }

    function getDowntimeJailDuration() external view returns (uint256) {
        return params[ParamKey.downtimeJailDuration];
    }

    function getSlashFractionDowntime() external view returns (uint256) {
        return params[ParamKey.slashFractionDowntime];
    }

    function getUnbondingTime() external view returns (uint256) {
       return params[ParamKey.unbondingTime];
    }

    function getSlashFractionDoubleSign() external view returns (uint256) {
        return params[ParamKey.slashFractionDoubleSign];
    }

    function getSignedBlockWindow() external view returns (uint256) {
        return params[ParamKey.signedBlockWindow];
    }

    function getMinSignedPerWindow() external view returns (uint256) {
       return params[ParamKey.minSignedPerWindow];
    }

    function getMinStake() external view returns (uint256) {
       return params[ParamKey.minStake];
    }

    function getMinValidatorStake() external view returns (uint256) {
        return params[ParamKey.minValidatorStake];
    }

    function getMinAmountChangeName() external view returns (uint256) {
        return params[ParamKey.minAmountChangeName];
    }

    function getMinSelfDelegation() external view returns (uint256) {
        return params[ParamKey.minSelfDelegation];
    }
}