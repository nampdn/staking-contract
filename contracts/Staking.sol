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
    }

    // Private
    uint256 private _oneDec = 1 * 10**18;
    address private _previousProposer;
    uint256 private _powerReduction = 1 * 10**8;
    Params public  params;
    address[] public allVals;
    mapping(address => address) public ownerOf;
    mapping(address => address) public valOf;
    mapping(address => uint256) public tokens;
    EnumerableSet.AddressSet currentValidatorSets;
    uint256 public totalSupply = 5000000000 * 10**18;
    uint256 public totalBonded;
    mapping(address => EnumerableSet.AddressSet) private valOfDel;
    Minter public minter;
    mapping(address => uint256) public rewards;


    // Functions with this modifier can only be executed by the validator
    modifier onlyValidator() {
        require(valOf[msg.sender] != address(0x0), "Ownable: caller is not the validator");
        _;
    }

    constructor() public {
        params = Params({
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
        bytes32 salt = keccak256(abi.encodePacked(name, commissionRate, commissionMaxRate, 
            commissionMaxChangeRate, minSelfDelegation, msg.sender));
        assembly {
            val := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IValidator(val).initialize(name, msg.sender, commissionRate, commissionMaxRate, 
            commissionMaxChangeRate, minSelfDelegation);
        allVals.push(val);
        ownerOf[msg.sender] = val;
        valOf[val] = msg.sender;
    }

    // Update signer address
    function updateSigner(address signerAddr) external onlyValidator {
        address oldSignerAddr = valOf[msg.sender];
        valOf[msg.sender] = signerAddr;
        ownerOf[oldSignerAddr] = address(0x0);
        ownerOf[signerAddr] = msg.sender;
    }

    function allValsLength() external view returns(uint) {
        return allVals.length;
    }

    function setPreviousProposer(address previousProposer) public onlyOwner {
        _previousProposer = previousProposer;
    }

    function finalize(
        address[] calldata _signers, 
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
            _allocateTokens(sumPreviousPrecommitPower,
                previousTotalPower, _signers, _votingPower
            );
        }
        _previousProposer = block.coinbase;
        for (uint256 i = 0; i < _votingPower.length; i++) {
            _validateSignature(_signers[i], _votingPower[i], _signed[i]);
        }
    }

    function _allocateTokens(
        uint256 sumPreviousPrecommitPower,
        uint256 totalPreviousVotingPower,
        address[] memory _signers,
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
        for (uint256 i = 0; i < _signers.length; i++) {
            uint256 powerFraction = powers[i].divTrun(totalPreviousVotingPower);
            uint256 _rewards = fees.mulTrun(voteMultiplier).mulTrun(
                powerFraction
            );
            _allocateTokensToValidator(_signers[i], _rewards);
        }
    }

    function _allocateTokensToValidator(address signerAddr, uint256 _rewards) private{
        IValidator(ownerOf[signerAddr]).allocateToken(_rewards);
        rewards[ownerOf[signerAddr]] = rewards[ownerOf[signerAddr]].add(_rewards);
    }

    function _validateSignature( address signerAddr, uint256 votingPower, bool signed) private {
        IValidator val = IValidator(ownerOf[signerAddr]);
        bool jailed = val.validateSignature(votingPower, signed);
        if (jailed) {
            currentValidatorSets.remove(ownerOf[signerAddr]);
        }
    }

    function withdrawRewards(address payable to, uint256 amount) external onlyValidator {
        to.transfer(amount);
    }

    function delegate(address delAddr, uint256 amount) external onlyValidator {
        valOfDel[delAddr].add(msg.sender);
        totalBonded = totalBonded.add(amount);
        tokens[msg.sender] = tokens[msg.sender].add(amount);
        _addCurrentValidatorSets(msg.sender);
    }

    function undelegate(uint256 amount) external onlyValidator {
        totalBonded = totalBonded.sub(amount);
        _setToken(msg.sender, tokens[msg.sender].sub(amount));
    } 

    function _addCurrentValidatorSets(address valAddr) private {
        if (tokens[valAddr] > 0 && tokens[valAddr].div(_powerReduction) > 0) {
            currentValidatorSets.add(msg.sender);
        }
    }

    function setToken(uint256 amount) external onlyValidator{
        _setToken(msg.sender, amount);
    }

    function _setToken(address valAddr, uint256 amount) private{
        tokens[valAddr] = amount;
        if (amount == 0 || amount.div(_powerReduction) == 0) {
            currentValidatorSets.remove(valAddr);
        }
    }

    function removeDelegation(address delAddr) external onlyValidator{
        valOfDel[delAddr].remove(msg.sender);
    }

    function burn(uint256 amount) external onlyValidator{
        totalBonded = totalBonded.sub(amount);
        totalSupply = totalSupply.sub(amount);
        _setToken(msg.sender, tokens[msg.sender].sub(amount));
    }

    // slash and jail validator forever
    function doubleSign(
        address signerAddr,
        uint256 votingPower,
        uint256 distributionHeight
    ) external onlyOwner {
        IValidator(ownerOf[signerAddr]).doubleSign(votingPower, distributionHeight);
        currentValidatorSets.remove(ownerOf[signerAddr]);
    }

    function mint() external onlyOwner returns (uint256) {
        uint256 fees =  minter.mint(); 
        totalSupply = totalSupply.add(fees);
        return fees;
    }

    // get validators of the delegator
    function getValidatorsByDelegator(address delAddr)
        public
        view
        returns (address[] memory)
    {
        uint256 total = valOfDel[delAddr].length();
        address[] memory valAddrs = new address[](total);
        for (uint256 i = 0; i < total; i++) {
            valAddrs[i] = valOfDel[delAddr].at(i);
        }
        return valAddrs;
    }

    // get current validator sets
    function getValidatorSets() external view returns (address[] memory, uint256[] memory) {
        uint256 total = currentValidatorSets.length();
        address[] memory signerAddrs = new address[](total);
        uint256[] memory votingPowers = new uint256[](total);
        for (uint256 i = 0; i < total; i++) {
            address valAddr = currentValidatorSets.at(i);
            signerAddrs[i] = valOf[valAddr];
            votingPowers[i] = tokens[valAddr].div(_powerReduction);
        }
        return (signerAddrs, votingPowers);
    }

    function deposit() external payable {
    }
}