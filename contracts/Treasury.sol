pragma solidity ^0.5.16;
import "./Staking.sol";

contract Treasury {

    event AddProposal(uint256 _value, address _from);
    event AddVote(uint256 _proposalId, address _from);
    event ConfirmProposal(uint256 _proposalId, address _from);
    event TransferToProposer(uint256 _amount, address _to);


    constructor(address _stakingAddress) public {
        stakingAddress = _stakingAddress;
    }

    struct Proposal {
        address proposer;
        uint256 value;
        uint256 startTime;
        uint256 endTime;
        mapping(address => bool) votes;
        uint256 deposit;
        bool isSuccess;
    }

    uint256 constant public MIN_STAKE = 5 * 10**23; // 500000 KAI
    uint256 constant public VOTING_PERIOD = 2592000; // 30 days
    Proposal[] public proposals;
    address public stakingAddress;

    function allProposal() public view returns (uint) {
        return proposals.length;
    }

    function addProposal(uint256 value) public payable {
        require(msg.value >= MIN_STAKE, "Deposit must greater or equal 10000 KAI");
        require(value <= address(this).balance, "Amount must lower or equal treasury balance");

        proposals.push(Proposal({
            value: value,
            proposer: msg.sender,
            deposit: msg.value,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            isSuccess: false
        }));

        emit AddProposal(value, msg.sender);
    }

    function addVote(uint256 proposalId) public {    
        require(proposalId < proposals.length, "Proposal not found");
        require(proposals[proposalId].endTime > block.timestamp, "Inactive proposal");
        proposals[proposalId].votes[msg.sender] = true;

        emit AddVote(proposalId, msg.sender);
    }

    function confirmProposal(uint proposalId) payable public {
        require(proposalId < proposals.length, "Proposal not found");
        require( proposals[proposalId].isSuccess != true, "Proposal successed");
        require(proposals[proposalId].proposer == msg.sender);

        address[] memory signers;
        uint256[] memory votingPowers;
        (signers, votingPowers) = Staking(stakingAddress).getValidatorSets();
        uint256 totalPowerVoteYes;
        uint256 totalVotingPowers;
        for (uint i = 0; i < signers.length; i ++) {
             totalVotingPowers = totalVotingPowers + votingPowers[i];
            if (proposals[proposalId].votes[signers[i]]) {
                totalPowerVoteYes = totalPowerVoteYes + votingPowers[i];
            }
        }

        uint256 quorum = (2 * totalVotingPowers)/3 + 1;
        if (totalPowerVoteYes < quorum) {
            return;
        }

        require(proposals[proposalId].deposit + proposals[proposalId].value <= address(this).balance, "Amount must lower or equal treasury balance");
        msg.sender.transfer(proposals[proposalId].deposit + proposals[proposalId].value);
        
        emit TransferToProposer(proposals[proposalId].deposit + proposals[proposalId].value, msg.sender);
        proposals[proposalId].isSuccess = true;

        emit ConfirmProposal(proposalId, msg.sender);
    }

    function getTreasuryBalance() view public returns (uint256) {
        return address(this).balance;
    }

    function getInforProposal(uint256 proposalId) view public returns (address[] memory) {
        address[] memory signers;
        uint256[] memory votingPowers;
        (signers, votingPowers) = Staking(stakingAddress).getValidatorSets();
        address[] memory voters = new address[](signers.length);
        uint256 totalPowerVoteYes;
        for (uint i = 0; i < signers.length; i ++) {
            if (proposals[proposalId].votes[signers[i]]) {
                totalPowerVoteYes = totalPowerVoteYes + votingPowers[i];
                voters[i] = signers[i];
            }
        }

        return voters;
    }

    function () external payable {
    }
}