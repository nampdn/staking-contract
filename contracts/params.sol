pragma solidity >=0.4.25 <0.7.0;


contract Params {
    enum ParamKey {
        VotingPeriod,
        MaxValidator,
        Deposit,
        // add staking param key here
        // add validator params key here
    }

    struct Proposal {
        address proposer;
        ParamKey key;
        uint256 value;
        uint256 startTime;
        uint256 endTime;
        mapping(address => bool) votes;
        uint256 deposit;
    }

    mapping(ParamKey => uint256) params;
    Proposal[] public proposals;

    function allProposal() public view returns (uint) {
        return proposals.length;
    }

    function addProposal(ParamKey key, uint256 value) public payable returns uint {
        require(msg.value >= params[ParamKey.Deposit], "min deposit")
        proposals.push(Proposal({
            key: key, 
            value: value,
            proposer: msg.sender,
            deposit: msg.value,
            startTime: block.timestamp,
            endTime: block.timestamp.add(params[ParamKey.VotingPeriod])
        }))
    }

    function addVote(uint proposalId, bool voteYes) public {
        require(proposals.length < proposalId, "proposal not found")
        require(proposals[proposalId].endTime > block.timestamp, "inactive proposal")
        proposals[proposalId].votes[msg.sender] = voteYes;
    }

    function confirmProposal(uint proposalId) public {
        require(proposals.length < proposalId, "proposal not found")
        (signers, votingPowers) = staking.getValidatorSets()
        uint256 totalPowerVoteYes;
        uint256 totalVotingPowers;
        for (uint i = 0; i < signers.length; i ++) {
            totalStakes = totalStakes.add(votingPowers[i])
            if (proposals[proposer].votes[signers[i]]) {
                totalPowerVoteYes = totalPowerVoteYes.add(votingPowers[i])
            }
        }
        uint256 quorum = totalVotingPowers.mul(2).div(3).add(1)
        if totalPowerVoteYes < quorum {
            // burn deposit token here
            return
        }
        params[proposals[proposalId].key] = proposals[proposalId].value;
        msg.sender.transfer(proposals[proposalId].deposit);
    }

}