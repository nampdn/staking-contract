// SPDX-License-Identifier: MIT
pragma solidity =0.5.16;
import "./interfaces/IStaking.sol";
import "./interfaces/IValidator.sol";
import "./Minter.sol";
import "./Safemath.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./Validator.sol";

contract Staking is IStaking, Ownable, Rank {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    struct Params {
        uint256 baseProposerReward;
        uint256 bonusProposerReward;
        uint256 maxValidators;
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
            baseProposerReward: 1 * 10**16,
            bonusProposerReward: 4 * 10**16
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

        for (uint256 i = 0; i < _votingPower.length; i++) {
            _validateSignature(_vals[i], _votingPower[i], _signed[i]);
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
        address payable val = address(uint160(ownerOf[valAddr]));
        val.transfer(rewards);
    }

    function _validateSignature( address valAddr, uint256 votingPower, bool signed) private {
        bool jailed = IValidator(ownerOf[valAddr]).validateSignature(votingPower, signed);
        if (jailed) {
            _removeValidatorRank(ownerOf[valAddr]);
        }
    }

    function delegate(address delAddr, uint256 amount) external onlyValidator {
        valOfDel[delAddr].add(msg.sender);
        totalBonded += amount;
        _validatorState[msg.sender].tokens += amount;
        addRank(msg.sender);
    }

    function decrementValidatorAmount(uint256 amount) external onlyValidator{
        totalBonded -= amount;
        _validatorState[msg.sender].tokens -= amount;
    }

    function removeDelegation(address delAddr) external onlyValidator{
        valOfDel[delAddr].remove(msg.sender);
    }

    function burn(uint256 amount) external onlyValidator{
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
        IValidator(ownerOf[valAddr]).doubleSign(votingPower, distributionHeight);
        _removeValidatorRank(ownerOf[valAddr]);
    }

    function getValidatorSets()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory addrs = new address[](maxVal);
        uint256[] memory powers = new uint256[](maxVal);

        for (uint256 i = 0; i < _rank.length; i++) {
            addrs[i] = _rank[i].addr;
            powers[i] = _rank[i].amount;
        }
        return (addrs, powers);
    }

    function applyAndReturnValidatorSets()
        external
        onlyOwner
        returns (address[] memory, uint256[] memory)
    {
        sortAndClean()
        return getValidatorSets();
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

    function () external payable {
    }
}