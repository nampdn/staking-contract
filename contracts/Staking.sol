pragma solidity >=0.5.0;
import "./interfaces/IStaking.sol";
import "./interfaces/IValidator.sol";
import "./interfaces/IMinter.sol";
import {SafeMath} from "./Safemath.sol";

contract Staking is IStaking {
    using SafeMath for uint256;
    struct Params {
        uint256 baseProposerReward;
        uint256 bonusProposerReward;
        uint256 maxValidators;
        uint256 downtimeJailDuration;
        uint256 slashFractionDowntime;
        uint256 unbondingTime;
        uint256 slashFractionDoubleSign;
        uint256 signedBlockWindow;
        uint256 minSignedPerWindow;
        // mint params
        uint256 inflationRateChange;
        uint256 goalBonded;
        uint256 blocksPerYear;
        uint256 inflationMax;
        uint256 inflationMin;
    }

    // Private
    uint256 private _oneDec = 1 * 10**18;
    // Previous Proposer
    address private _previousProposer;

    // Staking Params
    Params public  params;
    
    

    // create new validator
    function createValidator(string memory name, uint64 maxRate, uint64 maxChangeRate, uint64 minSelfDelegation) public payable{

    }


    function finalize(address[] memory valAddr, uint64[] memory votingPower, bool[] memory signed) external{
        uint256 previousTotalPower = 0;
        uint256 sumPreviousPrecommitPower = 0;
        for (uint256 i = 0; i < votingPower.length; i++) {
            previousTotalPower += votingPower[i];
            if (signed[i]) {
                sumPreviousPrecommitPower += votingPower[i];
            }
        }
         if (block.number > 1) {
            _allocateTokens(
                sumPreviousPrecommitPower,
                previousTotalPower,
                _previousProposer,
                valAddr,
                votingPower
            );
        }

        _previousProposer = block.coinbase;

        for (uint256 i = 0; i < votingPower.length; i++) {
            _validateSignature(valAddr[i], votingPower[i], signed[i]);
        }
    }

    function _allocateTokens(
        uint256 sumPreviousPrecommitPower,
        uint256 totalPreviousVotingPower,
        address[] memory addrs,
        uint256[] memory powers
    ) private {
        uint256 previousFractionVotes = sumPreviousPrecommitPower.divTrun(
            totalPreviousVotingPower
        );
        uint256 proposerMultiplier = params.baseProposerReward.add(
            params.bonusProposerReward.mulTrun(previousFractionVotes)
        );

        IMinter minter = IMinter();
        uint64 fees = minter.getFeesCollected();
        uint256 proposerReward = fees.mulTrun(proposerMultiplier);
        _allocateTokensToValidator(_previousProposer, proposerReward);

        uint256 voteMultiplier = oneDec;
        voteMultiplier = voteMultiplier.sub(proposerMultiplier);
        for (uint256 i = 0; i < addrs.length; i++) {
            uint256 powerFraction = powers[i].divTrun(totalPreviousVotingPower);
            uint256 rewards = fees.mulTrun(voteMultiplier).mulTrun(
                powerFraction
            );
            _allocateTokensToValidator(addrs[i], rewards);
        }
    }


    function _allocateTokensToValidator(address valAddr, uint256 rewards)
        private
    {
        IValidator(valAddr).allocateToken(rewards);
    }


    function _validateSignature(
        address valAddr,
        uint256 votingPower,
        bool signed
    ) private {
        IValidator(valAddr).validateSignature(votingPower, signed);
    }
}