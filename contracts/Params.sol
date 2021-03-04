pragma solidity ^0.5.0;
import {Ownable} from "./Ownable.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {SafeMath} from "./Safemath.sol";
import {IParams} from "./interfaces/IParams.sol";


contract Params is Ownable {

    event AddProposal(ParamKey[] _keys, uint256[] _values);
    event AddVote(uint _proposalId, VoteOption _option, address _from);
    event ConfirmProposal(uint _proposalId, address _from);
    event TransferToTreasury(uint _proposalId, address _from, address _to);

    enum ProposalStatus {
        Pending,
        Passed,
        Rejected
    }

    enum VoteOption {
        Abstain,
        Yes,
        No
    }

    enum ParamKey {
        // staking params
        baseProposerReward,
        bonusProposerReward,
        maxProposers, 

        // validator params :3
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

        // minter params : 13
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
        _setParam(ParamKey.baseProposerReward, 5 * 10**16); // 5%
        _setParam(ParamKey.bonusProposerReward, 5 * 10**16); // 5%
        _setParam(ParamKey.maxProposers, 20);

        // validator params 
        _setParam(ParamKey.downtimeJailDuration, 3600); // 1h
        _setParam(ParamKey.slashFractionDowntime, 1 * 10**15); // 0.1%
        _setParam(ParamKey.unbondingTime, 604800); // 7 days
        _setParam(ParamKey.slashFractionDoubleSign, 25 * 10**16); // 25%
        _setParam(ParamKey.signedBlockWindow, 10000); // 10,000 blocks per windows
        _setParam(ParamKey.minSignedPerWindow, 5 * 10**17); // 50%
        _setParam(ParamKey.minStake, 25 * 10**21); // 25,000 KAI
        _setParam(ParamKey.minValidatorStake, 125 * 10**23); // 12,5M KAI
        _setParam(ParamKey.minAmountChangeName, 1 *10**22); // 10,000 KAI
        _setParam(ParamKey.minSelfDelegation, 25 * 10**21); // 25,000 KAI

        // minter
        _setParam(ParamKey.inflationRateChange, 2 * 10**16); // 2%
        _setParam(ParamKey.goalBonded, 15 * 10**16); // 30% = 1,35 Bn KAI
        _setParam(ParamKey.blocksPerYear, 6307200); // 5s per block
        _setParam(ParamKey.inflationMax, 5 * 10**16); // 5%
        _setParam(ParamKey.inflationMin, 2 * 10**16); // 2%

        _setParam(ParamKey.Deposit, 5 * 10**23); // 500,000 KAI
        _setParam(ParamKey.VotingPeriod, 2592000); // 30 days
    }

    function _setParam(ParamKey key, uint256 value) internal {
        params[uint256(key)] = value; 
    }

    function _getParam(ParamKey key) private view returns (uint256) {
        return params[uint256(key)];
    }

    function getParam(ParamKey key) public view returns (uint256) {
        return _getParam(key);
    }

    function allProposal() public view returns (uint) {
        return proposals.length;
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

        emit AddProposal(keys, values);
        return proposals.length - 1;
    }

    function addVote(uint proposalId, VoteOption option) public {
        require(proposalId < proposals.length, "proposal not found");
        require(proposals[proposalId].endTime > block.timestamp, "inactive proposal");
        proposals[proposalId].votes[msg.sender] = option;

        emit AddVote(proposalId, option, msg.sender);
    }
    function confirmProposal(uint proposalId) public {
        require(proposalId < proposals.length, "proposal not found");
        require(proposals[proposalId].status == ProposalStatus.Pending, "proposal status pending");

        Proposal storage proposal = proposals[proposalId];
        uint256 voteYes;
        uint256 voteNo;
        uint256 voteAbsent;
        (voteYes,  voteNo, voteAbsent) = _getProposalPendingResults(proposalId);

        // update result
        proposal.results[uint(VoteOption.Yes)] = voteYes;
        proposal.results[uint(VoteOption.No)] = voteNo;
        proposal.results[uint(VoteOption.Abstain)] = voteAbsent;
        uint256 totalVotingPowers = voteYes + voteNo + voteAbsent;
        uint256 quorum = totalVotingPowers.mul(2).div(3).add(1);
        if (voteYes < quorum) {
            require(proposals[proposalId].endTime < block.timestamp, "Inactive proposal");
            proposal.status = ProposalStatus.Rejected;
            address(uint160(address(_staking.treasury()))).transfer(proposal.deposit);

            emit TransferToTreasury(proposalId, address(this), _staking.treasury());
            return;
        }

        // update params
        for (uint i = 0; i < proposal.keys.length; i ++) {
            _setParam(proposal.keys[i], proposal.values[i]);
        }
        // refund deposit
        proposal.proposer.transfer(proposals[proposalId].deposit);
        proposal.status = ProposalStatus.Passed;

        emit ConfirmProposal(proposalId, msg.sender);
    }

    function _getProposalPendingResults(uint proposalId) private view returns (uint256, uint256, uint256) {
        address[] memory signers;
        uint256[] memory votingPowers;
        (signers, votingPowers) = _staking.getValidatorSets();
        uint256 totalPowerVoteYes;
        uint256 totalPowerVoteNo;
        uint256 totalPowerVoteAbsent;
        for (uint i = 0; i < signers.length; i ++) {
            VoteOption voteOption = proposals[proposalId].votes[signers[i]];
            if (voteOption == VoteOption.Yes) {
                totalPowerVoteYes = totalPowerVoteYes.add(votingPowers[i]);
            } else if (voteOption == VoteOption.No) {
                totalPowerVoteNo = totalPowerVoteNo.add(votingPowers[i]);
            } else {
                totalPowerVoteAbsent = totalPowerVoteAbsent.add(votingPowers[i]);
            }
        }
        return (totalPowerVoteYes, totalPowerVoteNo, totalPowerVoteAbsent);
    }

    function getProposalDetails(uint proposalId) external view returns (uint256, uint256, uint256, ParamKey[] memory, uint256[] memory) {
        require(proposalId < proposals.length, "proposal not found");
        
        uint256 voteYes;
        uint256 voteNo;
        uint256 voteAbstain;

        if (proposals[proposalId].status == ProposalStatus.Pending) {
            (voteYes, voteNo, voteAbstain) = _getProposalPendingResults(proposalId);
        } else {
            voteYes = proposals[proposalId].results[uint(VoteOption.Yes)];
            voteNo = proposals[proposalId].results[uint(VoteOption.No)];
            voteAbstain = proposals[proposalId].results[uint(VoteOption.Abstain)];
        }
        return (
            voteYes,
            voteNo,
            voteAbstain,
            proposals[proposalId].keys,
            proposals[proposalId].values
        );
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