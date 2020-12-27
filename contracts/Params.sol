pragma solidity ^0.5.0;
import {Ownable} from "./Ownable.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {SafeMath} from "./Safemath.sol";
import {IParams} from "./interfaces/IParams.sol";


contract Params is Ownable {

    enum ProposalStatus {
        Passed,
        Rejected,
        Pending
    }

    enum VoteOption {
        Yes,
        No,
        Abstain
    }

    enum ParamKey {
        // staking params
        baseProposerReward,
        bonusProposerReward,
        maxProposers,

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
        ParamKey[] keys;
        uint256[] values;
        uint256 startTime;
        uint256 endTime;
        mapping(address => VoteOption) votes;
        uint256 deposit;
        ProposalStatus status;
        mapping (uint=>uint256) results;
    }

    IStaking private _staking;
    mapping(uint256 => uint256) public params;
    Proposal[] public proposals;


    constructor() public {
        _staking = IStaking(msg.sender);

        // staking params
        _setParam(ParamKey.baseProposerReward, 1 * 10**16);
        _setParam(ParamKey.bonusProposerReward, 4 * 10**16);
        _setParam(ParamKey.maxProposers, 20);

        // validator params 
        _setParam(ParamKey.downtimeJailDuration, 300);
        _setParam(ParamKey.slashFractionDowntime, 5 * 10**16);
        _setParam(ParamKey.unbondingTime, 300);
        _setParam(ParamKey.slashFractionDoubleSign, 25 * 10**16);
        _setParam(ParamKey.signedBlockWindow, 100);
        _setParam(ParamKey.minSignedPerWindow, 50 * 10**16);
        _setParam(ParamKey.minStake, 1 * 10**16);
        _setParam(ParamKey.minValidatorStake, 1 * 10**17);
        _setParam(ParamKey.minAmountChangeName, 1 *10**17);
        _setParam(ParamKey.minSelfDelegation, 1 * 10**17);

        // minter
        _setParam(ParamKey.inflationRateChange, 1 * 10**16);
        _setParam(ParamKey.goalBonded, 50 * 10**16);
        _setParam(ParamKey.blocksPerYear, 6307200);
        _setParam(ParamKey.inflationMax, 5 * 10**16);
        _setParam(ParamKey.inflationMin, 1 * 10**16);

        _setParam(ParamKey.Deposit, 1 * 10**17);
        _setParam(ParamKey.VotingPeriod, 604800); // 7 days
    }

    function _setParam(ParamKey key, uint256 value) internal {
        params[uint256(key)] = value; 
    }

    function _getParam(ParamKey key) public view returns (uint256) {
        return params[uint256(key)];
    }

    function addProposal(ParamKey[] memory keys, uint256[] memory values) public payable returns (uint) {
        require(msg.value >= _getParam(ParamKey.Deposit), "min deposit");
        proposals.push(Proposal({
            keys: keys, 
            values: values,
            proposer: msg.sender,
            deposit: msg.value,
            startTime: block.timestamp,
            endTime: block.timestamp.add(_getParam(ParamKey.VotingPeriod)),
            status: ProposalStatus.Pending
        }));
        return proposals.length - 1;
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
        (signers, votingPowers) = _staking.getValidatorSets();

        Proposal storage proposal = proposals[proposalId];
        uint256 totalVotingPowers;
        uint256 totalPowerVoteYes;
        uint256 totalPowerVoteNo;
        uint256 totalPowerVoteAbsent;
        for (uint i = 0; i < signers.length; i ++) {
            totalVotingPowers = totalVotingPowers.add(votingPowers[i]);
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
        proposal.results[uint(VoteOption.Yes)] = totalPowerVoteYes;
        proposal.results[uint(VoteOption.No)] = totalPowerVoteNo;
        proposal.results[uint(VoteOption.Abstain)] = totalPowerVoteAbsent;

        uint256 quorum = totalVotingPowers.mul(2).div(3).add(1);
        if (totalPowerVoteYes < quorum) {
            proposal.status = ProposalStatus.Rejected;
            // burn deposit token here
            return;
        }

        // update params
        for (uint i = 0; i < proposal.keys.length; i ++) {
            _setParam(proposal.keys[i], proposal.values[i]);
        }
        // refund deposit
        proposal.proposer.transfer(proposals[proposalId].deposit);
        proposal.status = ProposalStatus.Passed;
    }


    function getBaseProposerReward() external view returns (uint256) {
        return _getParam(ParamKey.baseProposerReward);
    }

    function getBonusProposerReward() external view returns (uint256) {
        return _getParam(ParamKey.bonusProposerReward);
    }

    function getMaxProposers() external view returns (uint256) {
        return _getParam(ParamKey.maxProposers);
    }

    function getInflationRateChange() external view returns (uint256) {
        return _getParam(ParamKey.inflationRateChange);
    }

    function getGoalBonded() external view returns (uint256) {
        return _getParam(ParamKey.goalBonded);
    }

    function getBlocksPerYear() external view returns (uint256) {
        return _getParam(ParamKey.blocksPerYear);
    }

    function getInflationMax() external view returns (uint256) {
        return _getParam(ParamKey.inflationMax);
    }

    function getInflationMin() external view returns (uint256) {
        return _getParam(ParamKey.inflationMin);
    }

    function getDowntimeJailDuration() external view returns (uint256) {
        return _getParam(ParamKey.downtimeJailDuration);
    }

    function getSlashFractionDowntime() external view returns (uint256) {
        return _getParam(ParamKey.slashFractionDowntime);
    }

    function getUnbondingTime() external view returns (uint256) {
       return _getParam(ParamKey.unbondingTime);
    }

    function getSlashFractionDoubleSign() external view returns (uint256) {
        return _getParam(ParamKey.slashFractionDoubleSign);
    }

    function getSignedBlockWindow() external view returns (uint256) {
        return _getParam(ParamKey.signedBlockWindow);
    }

    function getMinSignedPerWindow() external view returns (uint256) {
       return _getParam(ParamKey.minSignedPerWindow);
    }

    function getMinStake() external view returns (uint256) {
       return _getParam(ParamKey.minStake);
    }

    function getMinValidatorStake() external view returns (uint256) {
        return _getParam(ParamKey.minValidatorStake);
    }

    function getMinAmountChangeName() external view returns (uint256) {
        return _getParam(ParamKey.minAmountChangeName);
    }

    function getMinSelfDelegation() external view returns (uint256) {
        return _getParam(ParamKey.minSelfDelegation);
    }
}