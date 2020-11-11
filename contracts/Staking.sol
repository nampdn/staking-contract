pragma solidity >=0.5.0;
import {IStaking} from "./interfaces/IStaking.sol";
import {IValidator} from  "./interfaces/IValidator.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {Validator} from "./Validator.sol";
import {SafeMath} from "./Safemath.sol";
import {Ownable} from "./Ownable.sol";

contract Staking is IStaking, Ownable {
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
    }

    struct ValidatorState {
        uint64 amount;
    }

    // Private
    uint256 private _oneDec = 1 * 10**18;
    // Previous Proposer
    address private _previousProposer;

    // Staking Params
    Params public  params;
    address[] public allVals;
    mapping(address => address) public ownerOf;
    mapping(address => address) public valOf;
    mapping(address => ValidatorState) private _validatorState;


    constructor() public {
        params = Params({
            maxValidators: 100,
            downtimeJailDuration: 600,
            baseProposerReward: 1 * 10**16,
            bonusProposerReward: 4 * 10**16,
            slashFractionDowntime: 1 * 10**14,
            unbondingTime: 1814400,
            slashFractionDoubleSign: 5 * 10**16,
            signedBlockWindow: 100,
            minSignedPerWindow: 5 * 10**16
        });
    }


    // create new validator
    function createValidator(string calldata _name, uint64 _maxRate, uint64 _maxChangeRate, uint64 _minSelfDelegation) public{
        require(ownerOf[msg.sender] == address(0x0), "Valdiator owner exists");
        bytes memory bytecode = type(Validator).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_name, _maxRate, _maxChangeRate, _minSelfDelegation, msg.sender));
        assembly {
            val := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IValidator(val).initialize(_name, msg.sender, _maxRate, _maxChangeRate, _minSelfDelegation);
        allVals.push(val);
        onwerOf[msg.sender] = val;
        valOf[val] = msg.sender;
    }


    function finalize(address[] memory valAddr, uint64[] memory votingPower, bool[] memory signed) external onlyOwner{
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

    // update validator amount
    function updateValidatorAmount(uint64 amount) external{
        require(valOf[msg.sender] != address(0x0), "validator not found");
        _validatorState[msg.sender].amount = amount;
        // sort validator rank
    }



    function _allocateTokensToValidator(address valAddr, uint256 rewards)
        private
    {
        IValidator(ownerOf[valAddr]).allocateToken(rewards);
    }


    function _validateSignature(
        address valAddr,
        uint256 votingPower,
        bool signed
    ) private {
        IValidator(ownerOf[valAddr]).validateSignature(votingPower, signed);
    }
}