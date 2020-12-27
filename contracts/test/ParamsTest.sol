pragma solidity ^0.5.0;
import {Params} from "../Params.sol";

contract ParamsTest is Params {

    function confirmProposal(uint proposalId) public {
        require(proposalId < proposals.length, "proposal not found");
        Proposal storage proposal = proposals[proposalId];
        for (uint i = 0; i < proposal.keys.length; i ++) {
            _setParam(proposal.keys[i], proposal.values[i]);
        }
    }
}