// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;
import {IStaking} from "./interfaces/IStaking.sol";
import {IValidator} from  "./interfaces/IValidator.sol";
import {Minter} from "./Minter.sol";
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

    // validator rank
    address[] public rank;
    mapping(address => uint256) public valRank;
    bool private _neededSort; 

    Minter public minter;
    uint256 public totalSupply = 5000000000 * 10**18;
    uint256 public totalBonded;


    mapping(address => EnumerableSet.AddressSet) public valOfDel;

     // Functions with this modifier can only be executed by the validator
    modifier onlyValidator() {
        require(valOf[msg.sender] != address(0x0), "Ownable: caller is not the validator");
        _;
    }


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

        minter = new Minter();
        transferOwnership(address(this));
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

        uint64 fees = minter.feesCollected();
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

    function _updateValidatorAmount(address valAddr, uint64 amount) private {
        _validatorState[valAddr].amount = amount;
        if (amount > 0) {
            _addToRank(valAddr);
        } else {
            _removeValidatorRank(valAddr);
        }
    }


    function _allocateTokensToValidator(address valAddr, uint256 rewards) private{
        IValidator(ownerOf[valAddr]).allocateToken(rewards);
    }


    function _validateSignature( address valAddr, uint256 votingPower, bool signed) private {
        bool memory jailed = IValidator(ownerOf[valAddr]).validateSignature(votingPower, signed);
        if (jailed) {
            _updateValidatorAmount(ownerOf[valAddr], 0);
        }
    }

    
    function delegate(address delAddr, uint64 amount) external onlyValidator {
        valOfDel[delAddr].add(msg.sender);
        totalBonded += amount;
        _validatorState[msg.sender].amount += amount;
        _addToRank(msg.sender);
    }

    function undelegate(uint64 amount) external onlyValidator{
        totalBonded -= amount;
        _validatorState[msg.sender].amount -= amount;
        if (_validatorState[msg.sender].amount == 0) {
            _removeValidatorRank(msg.sender);
        }
    }

    function removeDelegation(address delAddr) external onlyValidator{
        valOfDel[delAddr].remove(msg.sender);
    }

    function burn(uint64 amount) external onlyValidator{
        totalBonded -= amount;
        totalSupply -= amount;
    }


    // slash and jail validator forever
    function doubleSign(
        address valAddr,
        uint256 votingPower,
        uint256 distributionHeight
    ) external onlyOwner {
        _doubleSign(valAddr, votingPower, distributionHeight);
    }


    function _doubleSign(
        address valAddr,
        uint256 votingPower,
        uint256 distributionHeight
    ) private {
        val = IValidator(ownerOf[valAddr]);
        val.slash(
            distributionHeight.sub(1),
            votingPower,
            _params.slashFractionDoubleSign
        );
        // // (Dec 31, 9999 - 23:59:59 GMT).
        val.jail(253402300799, true);
        _updateValidatorAmount(ownerOf[valAddr], 0);
    }


    function _addToRank(address valAddr) private {
        uint256 idx = valRank[valAddr];
        uint256 power = getValidatorPower(valAddr);
        if (power == 0) return;
        if (idx == 0) {
            rank.push(valAddr);
            rank[valAddr] = rank.length;
        }
        _neededSort = true;
    }


    function getValidatorPower(address valAddr) public view returns (uint256) {
        return validatorState[valAddr].tokens.div(powerReduction);
    }

     function getValidatorSets()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 maxVal = params.maxValidators;
        if (maxVal > rank.length) {
            maxVal = rank.length;
        }
        address[] memory valAddrs = new address[](maxVal);
        uint256[] memory powers = new uint256[](maxVal);

        for (uint256 i = 0; i < maxVal; i++) {
            valAddrs[i] = rank[i];
            powers[i] = getValidatorPower(rank[i]);
        }
        return (valAddrs, powers);
    }


    function applyAndReturnValidatorSets()
        external
        onlyOwner
        returns (address[] memory, uint256[] memory)
    {
        if (_neededSort && rank.length > 0) {
            _sortValRank(0, int256(rank.length - 1));
            for (uint256 i = valRanks.length; i > 300; i --) {
                delete valRank[rank[i - 1]];
                rank.pop();
            }
            _neededSort = false;
        }
        return getValidatorSets();
    }

    function _sortValRank(int256 left, int256 right) internal {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = getValPowerByRank(uint256(left + (right - left) / 2));
        while (i <= j) {
            while (getValPowerByRank(uint256(i)) > pivot) i++;
            while (pivot > getValPowerByRank(uint256(j))) j--;
            if (i <= j) {
                address tmp = rank[uint256(i)];
                rank[uint256(i)] = valRank[uint256(j)];
                rank[uint256(j)] = tmp;

                valRank[tmp] = uint256(j + 1);
                valRank[valRank[uint256(i)]] = uint256(i + 1);

                i++;
                j--;
            }
        }
        if (left < j) _sortValRank(left, j);
        if (i < right) _sortValRank(i, right);
    }

    function _removeValidatorRank(address valAddr) private {
        uint256 todDeleteIndex = valRank[valAddr];
        if (todDeleteIndex == 0) return;
        uint256 lastIndex = rank.length;
        address last = valRank[lastIndex - 1];
        rank[todDeleteIndex - 1] = last;
        valRank[last] = todDeleteIndex;
        rank.pop();
        delete valRank[valAddr];
        _neededSort = true;
    }


    function mint() public onlyOwner returns (uint256) {
        fees =  minter.mint(); 
        totalSupply += fees;
        return fees;
    }


    function getValidatorsByDelegator(address delAddr)
        public
        view
        returns (address[] memory)
    {
        uint256 total = valOfDel[delAddr].length();
        address[] memory addrs = new address[](total);
        for (uint256 i = 0; i < total; i++) {
            addrs[i] = valOfDel[delAddr].at(i);
        }

        return addrs;
    }
}