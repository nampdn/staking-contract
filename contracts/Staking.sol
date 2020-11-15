// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;
import "./interfaces/IStaking.sol";
import "./interfaces/IValidator.sol";
import "./Minter.sol";
import "./Safemath.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./Validator.sol";

contract Staking is IStaking, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
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
        uint256 tokens;
    }

    // Private
    uint256 private _oneDec = 1 * 10**18;
    // Previous Proposer
    address private _previousProposer;
    uint256 private _powerReduction = 1 * 10**8;
    // Staking Params
    Params public  params;
    address[] public allVals;
    mapping(address => address) public ownerOf;
    mapping(address => address) public valOf;
    mapping(address => ValidatorState) private _validatorState;
    address[] private _rank;
    mapping(address => uint256) private  _valRank;
    bool private _neededSort; 
    Minter public minter;
    uint256 public totalSupply = 5000000000 * 10**18;
    uint256 public totalBonded;

    mapping(address => EnumerableSet.AddressSet) private valOfDel;

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
    }

    // create new validator
    function createValidator(
        bytes32 name,
        uint256 commissionRate, 
        uint256 commissionMaxRate, 
        uint256 commissionMaxChangeRate, 
        uint256 minSelfDelegation
    ) external returns (address val) {
        require(ownerOf[msg.sender] == address(0x0), "Valdiator owner exists");
        bytes memory bytecode = type(Validator).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(name, commissionRate, commissionMaxRate, commissionMaxChangeRate, minSelfDelegation, msg.sender));
        assembly {
            val := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IValidator(val).initialize(name, msg.sender, commissionRate, commissionMaxRate, commissionMaxChangeRate, minSelfDelegation);
        allVals.push(val);
        ownerOf[msg.sender] = val;
        valOf[val] = msg.sender;
    }

    function allValsLength() external view returns(uint) {
        return allVals.length;
    }

    function setPreviousProposer(address previousProposer) public onlyOwner {
        _previousProposer = previousProposer;
    }

    function finalize(
        address[] calldata _vals, 
        uint256[] calldata _votingPower, 
        bool[] calldata _signed
    ) external onlyOwner{
        uint256 previousTotalPower = 0;
        uint256 sumPreviousPrecommitPower = 0;
        for (uint256 i = 0; i < _votingPower.length; i++) {
            previousTotalPower += _votingPower[i];
            if (_signed[i]) {
                sumPreviousPrecommitPower += _votingPower[i];
            }
        }
         if (block.number > 1) {
            _allocateTokens(
                sumPreviousPrecommitPower,
                previousTotalPower,
                _vals,
                _votingPower
            );
        }

        _previousProposer = block.coinbase;

        // for (uint256 i = 0; i < _votingPower.length; i++) {
        //     _validateSignature(_vals[i], _votingPower[i], _signed[i]);
        // }
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

        uint256 fees = minter.feesCollected();
        uint256 proposerReward = fees.mulTrun(proposerMultiplier);
        _allocateTokensToValidator(_previousProposer, proposerReward);

        uint256 voteMultiplier = _oneDec;
        voteMultiplier = voteMultiplier.sub(proposerMultiplier);
        for (uint256 i = 0; i < addrs.length; i++) {
            uint256 powerFraction = powers[i].divTrun(totalPreviousVotingPower);
            uint256 rewards = fees.mulTrun(voteMultiplier).mulTrun(
                powerFraction
            );
            _allocateTokensToValidator(addrs[i], rewards);
        }
    }

    function _allocateTokensToValidator(address valAddr, uint256 rewards) private{
        IValidator(ownerOf[valAddr]).allocateToken(rewards);
    }

    function _validateSignature( address valAddr, uint256 votingPower, bool signed) private {
        bool jailed = IValidator(ownerOf[valAddr]).validateSignature(
            votingPower, signed, params.signedBlockWindow, params.minSignedPerWindow,
            params.slashFractionDowntime, params.downtimeJailDuration
        );
        if (jailed) {
            _removeValidatorRank(ownerOf[valAddr]);
        }
    }

    function delegate(address delAddr, uint256 amount) external onlyValidator {
        valOfDel[delAddr].add(msg.sender);
        totalBonded += amount;
        _validatorState[msg.sender].tokens += amount;
        _addToRank(msg.sender);
    }

    function decrementValidatorAmount(uint256 amount) external onlyValidator{
        totalBonded -= amount;
        _validatorState[msg.sender].tokens -= amount;
        if (_validatorState[msg.sender].tokens == 0) {
            _removeValidatorRank(msg.sender);
        }
    }

    function removeDelegation(address delAddr) external onlyValidator{
        valOfDel[delAddr].remove(msg.sender);
    }

    function burn(uint64 amount) external onlyValidator{
        totalBonded -= amount;
        totalSupply -= amount;
        _validatorState[msg.sender].tokens -= amount;
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
        IValidator val = IValidator(ownerOf[valAddr]);
        val.slash(
            distributionHeight.sub(1),
            votingPower,
            params.slashFractionDoubleSign
        );
        // // (Dec 31, 9999 - 23:59:59 GMT).
        val.jail(253402300799, true);
        _removeValidatorRank(ownerOf[valAddr]);
    }

    function _addToRank(address valAddr) private {
        uint256 idx = _valRank[valAddr];
        uint256 power = _getValidatorPower(valAddr);
        if (power == 0) return;
        if (idx == 0) {
            _rank.push(valAddr);
            _valRank[valAddr] = _rank.length;
        }
        _neededSort = true;
    }

    function _getValidatorPower(address valAddr) private view returns (uint256) {
        return _validatorState[valAddr].tokens.div(_powerReduction);
    }

    function getValidatorSets()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 maxVal = params.maxValidators;
        if (maxVal > _rank.length) {
            maxVal = _rank.length;
        }
        address[] memory valAddrs = new address[](maxVal);
        uint256[] memory powers = new uint256[](maxVal);

        for (uint256 i = 0; i < maxVal; i++) {
            valAddrs[i] = valOf[_rank[i]];
            powers[i] = _getValidatorPower(_rank[i]);
        }
        return (valAddrs, powers);
    }

    function applyAndReturnValidatorSets()
        external
        onlyOwner
        returns (address[] memory, uint256[] memory)
    {
        if (_neededSort && _rank.length > 0) {
            _sortValRank(0, int256(_rank.length - 1));
            for (uint256 i = _rank.length; i > 300; i --) {
                delete _valRank[_rank[i - 1]];
                _rank.pop();
            }
            _neededSort = false;
        }
        return getValidatorSets();
    }

    function _getValPowerByRank(uint256 rank) private view returns (uint256) {
        return _getValidatorPower(_rank[rank]);
    }

    function _sortValRank(int256 left, int256 right) internal {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = _getValPowerByRank(uint256(left + (right - left) / 2));
        while (i <= j) {
            while (_getValPowerByRank(uint256(i)) > pivot) i++;
            while (pivot > _getValPowerByRank(uint256(j))) j--;
            if (i <= j) {
                address tmp = _rank[uint256(i)];
                _rank[uint256(i)] = _rank[uint256(j)];
                _rank[uint256(j)] = tmp;

                _valRank[tmp] = uint256(j + 1);
                _valRank[_rank[uint256(i)]] = uint256(i + 1);

                i++;
                j--;
            }
        }
        if (left < j) _sortValRank(left, j);
        if (i < right) _sortValRank(i, right);
    }

    function _removeValidatorRank(address valAddr) private {
        uint256 todDeleteIndex = _valRank[valAddr];
        if (todDeleteIndex == 0) return;
        uint256 lastIndex = _rank.length;
        address last = _rank[lastIndex - 1];
        _rank[todDeleteIndex - 1] = last;
        _valRank[last] = todDeleteIndex;
        _rank.pop();
        delete _valRank[valAddr];
        _neededSort = true;
    }

    function mint() external onlyOwner returns (uint256) {
        uint256 fees =  minter.mint(); 
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