pragma solidity >=0.4.21 <0.7.0;
import {SafeMath} from "./Safemath.sol";



contract Staking {
    using SafeMath for uint256;
    
    uint256 oneDec = 1 * 10 ** 18;

    struct Delegation {
        uint256 shares;
        address owner;
    }
    
    struct UBDEntry {
        uint256 amount;
        uint256 blockHeight;
        uint256 completionTime;
    }
    
    
    struct ValidatorCommission {
        uint256 rate;
    }
    
    struct Validator {
        address owner;
        uint256 tokens;
        uint256 delegationShares;
        bool jailed;
        ValidatorCommission commission;
    }
    
    struct DelegatorStartingInfo {
        uint256 stake;
        uint256 previousPeriod;
        uint256 height;
        
    }
    
    struct ValidatorSlashEvent {
        uint256 validatorPeriod;
        uint256 fraction;
        uint256 height;
    }
    
    struct ValidatorCurrentReward {
        uint256 period;
        uint256 reward;
    }
    
    struct ValidatorHistoricalRewards {
        uint256 cumulativeRewardRatio;
        uint reference_count;
    }
    
    struct ValidatorSigningInfo {
        uint256 startHeight;
        uint256 indexOffset;
        bool tombstoned;
        uint missedBlockCounter;
        uint256 jailedUntil;
    }
    
    
    struct Params {
        uint256 baseProposerReward;
        uint256 bonusProposerReward;
        uint256 maxValidators;
        uint256 maxMissed;
        uint256 downtimeJailDuration;
        uint256 slashFractionDowntime;
        uint256 unboudingTime;
        uint256 slashFractionDoubleSign;
        uint256 signedBlockWindown;
        uint256 minSignedPerWindown;
    
        // mint params
        uint256 inflationRateChange;
        uint256 goalBonded;
        uint256 blocksPerYear;
        uint256 inflationMax;
        uint256 inflationMin;
    }
    
    
    Validator[] validators;
    mapping(address => mapping(address => uint)) delegationsIndex;
    mapping(address => mapping(address => UBDEntry[])) unbondingEntries;
    mapping(address => mapping(address => DelegatorStartingInfo)) delegatorStartingInfo;
    mapping(address => ValidatorSlashEvent[]) validatorSlashEvents;
    mapping(address => ValidatorCurrentReward) validatorCurrentRewards;
    mapping(address => ValidatorHistoricalRewards[]) validatorHistoricalRewards;
    mapping(address => bool[1000]) validatorMissedBlockBitArray;
    mapping(address => ValidatorSigningInfo) validatorSigningInfos;
    mapping(address => uint256) validatorAccumulatedCommission;
    mapping(address => Delegation[]) delegations;
    mapping(address => uint) validatorsIndex;
    mapping(address => address[]) delegatorValidators;
    mapping(address => mapping(address => uint)) delegatorValidatorsIndex;
    
    // supply
    uint256 public totalSupply = 5000000000 * 10 ** 18;
    uint256 public totalBonded;
    uint256 public inflation;
    uint256 public annualProvision;
    uint256 _feesCollected;
    
    
    
    // mint
    
    Params _params;
    address _previousProposer;
    
    
    constructor() public {
        _params = Params({
            // staking params
            maxValidators: 100,
            maxMissed: 10000,
            downtimeJailDuration: 600, // 10 minutes,
            baseProposerReward: 1 * 10 ** 16, // 1%,
            bonusProposerReward: 4 * 10 ** 16, // 4%,
            slashFractionDowntime: 1 * 10 ** 14, // 0.01%,
            unboudingTime: 1814400, // 21 days
            slashFractionDoubleSign: 5 * 10 ** 16, // 5%,
            signedBlockWindown: 1000,
            minSignedPerWindown: 10,

            // minted params
            inflationRateChange: 13 * 10 ** 16, // 13%
            goalBonded: 67 * 10 ** 16, // 67%
            blocksPerYear: 6311520,
            inflationMax: 20 * 10 ** 16, // 20%
            inflationMin: 7 * 10 ** 16 // 7%
        });
    }
    
    modifier onlyRoot() {
        //require (msg.sender == root, "permission denied");
        _;
    }
    
    
    function createValidator(uint256 commssionRate) public payable {
        _createValidator(msg.sender, msg.value, commssionRate);
    }
    
    function _createValidator(address payable valAddr, uint256 amount, uint256 commssionRate) private{
        require(validatorsIndex[valAddr] == 0, "validator owner exists");
        require(amount > 0, "invalid delegation amount");
        ValidatorCommission memory commission = ValidatorCommission({
            rate: commssionRate
        });
        validators.push(Validator({
            owner: valAddr, 
            tokens: 0, 
            delegationShares: 0, 
            jailed: false, 
            commission: commission
        }));
        validatorsIndex[valAddr] = validators.length;
        _afterValidatorCreated(valAddr);
        _delegate(valAddr, valAddr, amount);
    }
    
    function _afterValidatorCreated(address valAddr) private {
        _initializeValidator(valAddr);
    }
    
    function _afterDelegationModified(address valAddr, address delAddr) private {
        _initializeDelegation(valAddr, delAddr);
    }
    
    
    function _delegate(address payable delAddr, address valAddr, uint256 amount) private {
        uint delIndex = delegationsIndex[valAddr][delAddr];
        // add delegation if not exists;
        if (delIndex == 0) {
            delegations[valAddr].push(Delegation({
                owner: delAddr,
                shares: 0
            }));
            delIndex = delegations[valAddr].length;
            delegationsIndex[valAddr][delAddr] = delIndex;
            
            // delegator validators index
            delegatorValidators[delAddr].push(valAddr);
            delegatorValidatorsIndex[delAddr][valAddr] = delegatorValidators[delAddr].length;
            
            _beforeDelegationCreated(valAddr);
        } else {
            _beforeDelegationSharesModified(valAddr, delAddr);
        }
        
        uint256 shared = _addTokenFromDel(valAddr, amount);
        
        totalBonded += amount;
        
        // increment stake amount
        Delegation storage del = delegations[valAddr][delIndex -1];
        del.shares += shared;
        _afterDelegationModified(valAddr, delAddr);
        
    }
    
    function _addTokenFromDel(address valAddr, uint256 amount) private returns (uint256) {
        Validator storage val = validators[validatorsIndex[valAddr]-1];
        uint256 issuedShares = 0;
        if (val.tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(valAddr, amount);
        }
        val.tokens +=amount;
        val.delegationShares += issuedShares;
        return issuedShares;
    }
    
    
    function delegate(address valAddr) public payable {
        require(validatorsIndex[valAddr] > 0, "validator not found");
        require(msg.value > 0, "invalid delegation amount");
        _delegate(msg.sender, valAddr, msg.value);
    }
    
    function _undelegate(address valAddr, address payable delAddr, uint256 amount) private {
        require(unbondingEntries[valAddr][delAddr].length < 7, "too many unbonding delegation entries");
        uint delegationIndex = delegationsIndex[valAddr][delAddr];
        require(delegationIndex > 0, "delegation not found");
        _beforeDelegationSharesModified(valAddr, delAddr);
        
        Validator storage val = validators[validatorsIndex[valAddr]-1];
        Delegation storage del = delegations[valAddr][delegationIndex -1];
        uint256 shares = _shareFromToken(valAddr, amount);
        require(del.shares >= shares, "invalid undelegate amount");
        del.shares -= shares;
        
        if (del.shares == 0) {
            _removeDelegation(valAddr, delAddr);
        } else {
            _afterDelegationModified(valAddr, delAddr);
        }
        
        uint256 amountRemoved = _removeDelShares(valAddr, shares);
        if (val.delegationShares == 0) {
            _removeValidator(valAddr);
        }
        
        unbondingEntries[valAddr][delAddr].push(UBDEntry({
            completionTime: block.timestamp.add(_params.unboudingTime),
            blockHeight: block.number,
            amount: amountRemoved
        }));
    }
    
    function _removeDelShares(address valAddr, uint256 shares) private returns (uint256) {
        Validator storage val = validators[validatorsIndex[valAddr] - 1];
        uint256 remainingShares = val.delegationShares;
        uint256 issuedTokens = 0;
        remainingShares = remainingShares.sub(shares);
        if (remainingShares == 0) {
            val.tokens = 0;
        } else {
            issuedTokens = _tokenFromShare(valAddr, shares);
            val.tokens = val.tokens.sub(issuedTokens);
        }
        val.delegationShares = remainingShares;
        return issuedTokens;
    }
    
    function undelegate(address valAddr, uint256 amount) public {
        require(amount > 0, "invalid undelegate amount");
        _undelegate(valAddr, msg.sender, amount);
    }
    
    function _jail(address valAddr) private {
        validators[validatorsIndex[valAddr]-1].jailed = true;
    }
    
    
    function _slash(address valAddr, uint256 infrationHeight, uint256 power, uint256 slashFactor) private {
        require(infrationHeight <= block.number, "");
        Validator storage val = validators[validatorsIndex[valAddr]-1];
        uint256 slashAmount = power.mul(slashFactor);
        if (infrationHeight < block.number) {
            for (uint i = 0; i < delegations[valAddr].length; i ++) {
                UBDEntry[] storage entries = unbondingEntries[valAddr][delegations[valAddr][i].owner];
                for (uint j = 0; j < entries.length; j ++) {
                    UBDEntry storage entry = entries[j];
                    if (entry.blockHeight > infrationHeight) {
                        uint256 amountSlashed = entry.amount.mul(slashFactor);
                        entry.amount -= amountSlashed;
                        slashAmount -= amountSlashed;
                    }
                }
            }
        }
        val.tokens -= slashAmount;
        _updateValidatorSlashFraction(valAddr, slashFactor);
        _burn(slashAmount);
    }
    
    
    function _burn(uint256 amount) private {
        totalBonded -= amount;
        totalSupply -= amount;
    }
    
    function _updateValidatorSlashFraction(address valAddr, uint256 fraction) private {
        uint256 newPeriod = _incrementValidatorPeriod(valAddr);
        _incrementReferenceCount(valAddr, newPeriod);
        validatorSlashEvents[valAddr].push(ValidatorSlashEvent({validatorPeriod: newPeriod, fraction: fraction, height: block.number}));
    }
    
    
    function _withdraw(address valAddr, address payable delAddr) private{
        UBDEntry[] storage entries= unbondingEntries[valAddr][delAddr];
        uint256 amount = 0;
        for (uint i = 0; i < entries.length; i ++) {
            if (entries[i].completionTime < block.timestamp) {
                amount += entries[i].amount;
                entries[i] = entries[entries.length - 1];
                entries.pop();
            }
        }
        require(amount > 0, "no unbonding amount to withdraw");
        delAddr.transfer(amount);
        totalBonded -= amount;
    }
    
    function _removeDelegation(address valAddr, address delAddr) private {
        
        // delete delegation and delegation index
        uint delegationIndex = delegationsIndex[valAddr][delAddr];
        uint lastDelegationIndex = delegations[valAddr].length;
        Delegation memory lastDelegation = delegations[valAddr][lastDelegationIndex -1];
        delegations[valAddr][delegationIndex-1] = lastDelegation;
        delegations[valAddr].pop();
        delegationsIndex[valAddr][lastDelegation.owner] = delegationIndex;
        
        // delete other info
        delete delegationsIndex[valAddr][delAddr];
        delete delegatorStartingInfo[valAddr][delAddr];
        
        
        // delete delegator validator index
        uint delValIndex = delegatorValidatorsIndex[delAddr][valAddr];
        delegatorValidators[delAddr][delValIndex-1] = delegatorValidators[delAddr][delegatorValidators[delAddr].length-1];
        delegatorValidators[delAddr].pop();
        delete delegatorValidatorsIndex[delAddr][valAddr];
    }
    
    function _removeValidator(address valAddr) private{
        // remove validator
        uint validatorIndex = validatorsIndex[valAddr];
        uint lastValidatorIndex = validators.length;
        Validator memory lastValidator = validators[lastValidatorIndex -1];
        validators[validatorIndex-1] = lastValidator;
        validators.pop();
        validatorsIndex[lastValidator.owner] = validatorIndex;
        delete validatorsIndex[valAddr];

        // remove other index
        delete validatorSlashEvents[valAddr];
        delete validatorAccumulatedCommission[valAddr];
        delete validatorHistoricalRewards[valAddr];
        delete validatorCurrentRewards[valAddr];
    }
    
    
    function withdraw(address valAddr) public {
        _withdraw(valAddr, msg.sender);
    }
    
    
    function _calculateDelegationRewards(address valAddr, address delAddr, uint256 endingPeriod) private view returns(uint256) {
        DelegatorStartingInfo memory startingInfo = delegatorStartingInfo[valAddr][delAddr];
        uint256 rewards = 0;
        for (uint256 i = 0; i < validatorSlashEvents[valAddr].length; i ++) {
            ValidatorSlashEvent memory slashEvent = validatorSlashEvents[valAddr][i];
             if (slashEvent.height > startingInfo.height &&
                slashEvent.height < block.number) {
                    endingPeriod = slashEvent.validatorPeriod;
                    if (endingPeriod > startingInfo.previousPeriod) {
                        rewards  += _calculateDelegationRewardsBetween(valAddr, startingInfo.previousPeriod, slashEvent.validatorPeriod, startingInfo.stake);
                        startingInfo.stake = startingInfo.stake.mul(slashEvent.fraction);
                        startingInfo.previousPeriod = endingPeriod;
                    }
                }
        }
        rewards += _calculateDelegationRewardsBetween(valAddr, startingInfo.previousPeriod, endingPeriod, startingInfo.stake);
        return rewards;
        
    }
    
    function _calculateDelegationRewardsBetween(address valAddr, uint startingPeriod, uint endingPeriod, uint256 stake) private view returns(uint256){
        ValidatorHistoricalRewards memory starting = validatorHistoricalRewards[valAddr][startingPeriod];
        ValidatorHistoricalRewards memory ending = validatorHistoricalRewards[valAddr][endingPeriod];
        uint256 difference = ending.cumulativeRewardRatio.sub(starting.cumulativeRewardRatio);
        return stake.mul(difference);
    }
    
    
    function _incrementValidatorPeriod(address valAddr) private returns(uint256){
        Validator memory val = validators[validatorsIndex[valAddr]-1];
        ValidatorCurrentReward storage rewards = validatorCurrentRewards[valAddr];
        uint256 previousPeriod = rewards.period -1;
        uint256 current = 0;
        if (rewards.reward > 0) {
            current = rewards.reward.divTrun(val.tokens);
        }
        uint256 historical = validatorHistoricalRewards[valAddr][previousPeriod].cumulativeRewardRatio;
        _decrementReferenceCount(valAddr, rewards.period-1);
        validatorHistoricalRewards[valAddr].push(ValidatorHistoricalRewards({
            cumulativeRewardRatio: historical.add(current), 
            reference_count:1
        }));
        rewards.period++;
        rewards.reward = 0;
        return previousPeriod;
        
    }
    
    function _decrementReferenceCount(address valAddr, uint256 period) private {
        validatorHistoricalRewards[valAddr][period].reference_count--;
        if (validatorHistoricalRewards[valAddr][period].reference_count == 0) {
            delete validatorHistoricalRewards[valAddr][period];
        }
    }
    
    function _incrementReferenceCount(address valAddr, uint256 period) private {
         validatorHistoricalRewards[valAddr][period].reference_count++;
    }
    
    
    function _initializeDelegation(address valAddr, address delAddr) private {
        uint256 delegationIndex = delegationsIndex[valAddr][delAddr]-1;
        uint256 previousPeriod = validatorCurrentRewards[valAddr].period -1;
        _incrementReferenceCount(valAddr, previousPeriod);
        delegatorStartingInfo[valAddr][delAddr].height = block.number;
        delegatorStartingInfo[valAddr][delAddr].previousPeriod = previousPeriod;
        uint256 stake = _tokenFromShare(valAddr,delegations[valAddr][delegationIndex].shares);
        delegatorStartingInfo[valAddr][delAddr].stake = stake;
    }
    
    function _initializeValidator(address valAddr) private {
        validatorHistoricalRewards[valAddr].push(ValidatorHistoricalRewards({
            reference_count: 1, 
            cumulativeRewardRatio: 0
        }));
        validatorCurrentRewards[valAddr].period = 1;
        validatorCurrentRewards[valAddr].reward = 0;
        validatorAccumulatedCommission[valAddr] = 0;
    }
    
    
    function _beforeDelegationCreated(address valAddr) private {
        _incrementValidatorPeriod(valAddr);
    }
    
    function _beforeDelegationSharesModified(address valAddr, address payable delAddr) private {
        _withdrawRewards(valAddr, delAddr);
    }
    
    function _withdrawRewards(address valAddr, address payable delAddr) private {
        uint256 endingPeriod = _incrementValidatorPeriod(valAddr);
        uint256 rewards = _calculateDelegationRewards(valAddr, delAddr, endingPeriod);
        _decrementReferenceCount(valAddr, delegatorStartingInfo[valAddr][delAddr].previousPeriod);
        delete delegatorStartingInfo[valAddr][delAddr];
        delAddr.transfer(rewards);
    }
    
    function withdrawReward(address valAddr) public {
        require(validatorsIndex[valAddr] > 0, "validator not found");
        require(delegationsIndex[valAddr][msg.sender] > 0, "delegator not found");
        _withdrawRewards(valAddr, msg.sender);
        _initializeDelegation(valAddr, msg.sender);
    }
    
    function getDelegationRewards(address valAddr, address delAddr) public view returns(uint256){
        require(validatorsIndex[valAddr] > 0, "validator not found");
        require(delegationsIndex[valAddr][delAddr] > 0, "delegation not found");
        Validator memory val = validators[validatorsIndex[valAddr] - 1];
        Delegation memory del = delegations[valAddr][delegationsIndex[valAddr][delAddr]-1];
        uint rewards =  _calculateDelegationRewards(valAddr, delAddr, validatorCurrentRewards[valAddr].period);
        // current reward
        rewards += _tokenFromShare(valAddr, del.shares).mulTrun(validatorCurrentRewards[valAddr].reward.divTrun(val.tokens));
        return rewards;
    }
    
    
    function _withdrawValidatorCommission(address payable valAddr) private {
        require(validators[validatorsIndex[valAddr]-1].owner != address(0x0), "validator does not exists");
        require(validatorAccumulatedCommission[valAddr] > 0, "no validator commission to reward");
        valAddr.transfer(validatorAccumulatedCommission[valAddr]);
        validatorAccumulatedCommission[valAddr] = 0;
    }
    
    function withdrawValidatorCommission() public {
        _withdrawValidatorCommission(msg.sender);
    }
    
    function getValidator(address valAddr) public view returns(address, uint256, uint256) {
        require(validatorsIndex[valAddr] > 0, "validator not found");
        uint256 valIndex = validatorsIndex[valAddr] - 1;
        return (
            validators[valIndex].owner,
            validators[valIndex].tokens,
            validators[valIndex].delegationShares
        );
    }
    
    
    function getValidatorDelegations(address valAddr) public view returns (address[] memory, uint256[] memory) {
        require(validatorsIndex[valAddr] > 0, "validator not found");
        address[] memory dels = new address[](delegations[valAddr].length);
        uint256[] memory shares = new uint256[](delegations[valAddr].length);
        for (uint i = 0; i < delegations[valAddr].length; i ++) {
            dels[i] = delegations[valAddr][i].owner;
            shares[i] = delegations[valAddr][i].shares;
        }
        return (dels, shares);
    }
    
    function getDelegation(address valAddr, address delAddr) public view returns (address, uint256) {
        uint delIndex = delegationsIndex[valAddr][delAddr];
        require(delIndex > 0, "delegation not found");
        Delegation memory del = delegations[valAddr][delIndex - 1];
        return (
            del.owner,
            del.shares
        );
    }
    
    function getDelegatorValidators(address delAddr) public view returns (address[] memory) {
        return delegatorValidators[delAddr];
    }
    
    function getValidatorCommission(address valAddr) public view returns (uint256) {
        return validatorAccumulatedCommission[valAddr];
    }
    
    
    function getAllDelegatorRewards(address delAddr) public view returns (uint256) {
        uint256 rewards = 0;
        for (uint i = 0; i < delegatorValidators[delAddr].length; i ++) {
            rewards += getDelegationRewards(delegatorValidators[delAddr][i], delAddr);
        }
        return rewards;
    }
    
    function getDelegatorStake(address valAddr, address delAddr) public view returns (uint256) {
        uint delIndex = delegationsIndex[valAddr][delAddr];
        require(delIndex > 0, "delegation not found");
        Delegation memory del = delegations[valAddr][delIndex-1];
        return _tokenFromShare(valAddr, del.shares);
    }
    
    function getAllDelegatorStake(address delAddr) public view returns (uint256) {
        uint256 stake = 0;
        for (uint i = 0; i < delegatorValidators[delAddr].length; i ++) {
            stake += getDelegatorStake(delegatorValidators[delAddr][i], delAddr);
        }
        return stake;
    }
    
    function _tokenFromShare(address valAddr, uint256 shares) private view returns (uint256) {
       uint valIndex = validatorsIndex[valAddr];
       Validator memory val = validators[valIndex-1];
       return shares.mulTrun(val.tokens).divTrun(val.delegationShares);
    }
    
    function _shareFromToken(address valAddr, uint256 amount) private view returns (uint256) {
        uint valIndex = validatorsIndex[valAddr];
       Validator memory val = validators[valIndex-1];
       return val.delegationShares.mulTrun(amount).divTrun(val.tokens);
    }
    
    
    function getUBDEntries(address valAddr, address delAddr) public view returns (uint256[] memory, uint256[] memory) {
        uint256[] memory balances = new uint256[](unbondingEntries[valAddr][delAddr].length);
        uint256[] memory completionTime = new uint256[](unbondingEntries[valAddr][delAddr].length);
        for (uint i =0; i < unbondingEntries[valAddr][delAddr].length; i ++) {
            completionTime[i] = unbondingEntries[valAddr][delAddr][i].completionTime;
            balances[i] = unbondingEntries[valAddr][delAddr][i].amount;
        }
        return (balances, completionTime);
    }
    
    
    function _doubleSign(address valAddr, uint256 votingPower, uint256 distributionHeight) private {
        _slash(valAddr, distributionHeight, votingPower, _params.slashFractionDoubleSign); 
    }
    
    function doubleSign(address valAddr, uint256 votingPower, uint256 distributionHeight) public {
        _doubleSign(valAddr, votingPower, distributionHeight);
    }
    
    function _validateSignature(address valAddr, uint256 votingPower, bool signed) private{
        Validator storage val = validators[validatorsIndex[valAddr]-1];
        ValidatorSigningInfo storage signInfo = validatorSigningInfos[valAddr];
        uint index = signInfo.indexOffset % _params.signedBlockWindown;
        signInfo.indexOffset++;
        bool previous = validatorMissedBlockBitArray[valAddr][index];
        bool missed = !signed;
        if (!previous && missed) {
            signInfo.missedBlockCounter++;
            validatorMissedBlockBitArray[valAddr][index] = true;
        } else if (previous && !missed) {
            signInfo.missedBlockCounter--;
            validatorMissedBlockBitArray[valAddr][index] = false;
        }
        
        uint256 minHeight = signInfo.startHeight + _params.signedBlockWindown;
        uint maxMissed = _params.signedBlockWindown - _params.minSignedPerWindown;
        if (block.number > minHeight && signInfo.missedBlockCounter > maxMissed) {
            if (!val.jailed) {
                _slash(valAddr, block.number, votingPower, _params.slashFractionDowntime);
                _jail(valAddr);
                signInfo.jailedUntil = block.timestamp.add(_params.downtimeJailDuration);
                signInfo.missedBlockCounter = 0;
                signInfo.indexOffset = 0;
                delete validatorMissedBlockBitArray[valAddr];
            }
        }
        
    }
    
    function _allocateTokens(uint256 sumPreviousPrecommitPower, uint256 totalPreviousVotingPower, 
        address previousProposer, address[] memory vals, uint256[] memory powers) private{
        uint256 previousFractionVotes = sumPreviousPrecommitPower.divTrun(totalPreviousVotingPower);
        uint256 proposerMultiplier = _params.baseProposerReward.add(_params.baseProposerReward.mul(previousFractionVotes));
        uint256 proposerReward = _feesCollected.mulTrun(proposerMultiplier);
        _allocateTokensToValidator(previousProposer, proposerReward);
        _feesCollected -= proposerReward;
        
        uint256 voteMultiplier = 1 - proposerMultiplier;
        for (uint i = 0; i < vals.length; i ++) {
            uint256 powerFraction = powers[i].divTrun(totalPreviousVotingPower);
            uint256 rewards = _feesCollected.mulTrun(voteMultiplier).mulTrun(powerFraction);
            _allocateTokensToValidator(vals[0], rewards);
            _feesCollected -= rewards;
        }
    }
    
    function _allocateTokensToValidator(address valAddr, uint256 rewards) private{
        uint256 commission = rewards.mulTrun(validators[validatorsIndex[valAddr]-1].commission.rate);
        uint256 shared = rewards.sub(commission);
        validatorAccumulatedCommission[valAddr] += commission;
        validatorCurrentRewards[valAddr].reward += shared;
    }
    
    
    function _finalizeCommit(address[] memory vals, uint256[] memory powers, bool[] memory signed) private {
        uint256 previousTotalPower = 0;
        uint256 sumPreviousPrecommitPower = 0;
        for (uint i = 0; i < powers.length; i ++) {
            _validateSignature(vals[i], powers[i], signed[i]);
            previousTotalPower += powers[i];
            if (signed[i]) {
                sumPreviousPrecommitPower += powers[i];
            }
        }
        if (block.number > 1) {
            _allocateTokens(sumPreviousPrecommitPower, previousTotalPower, _previousProposer, vals, powers);
        }
        _previousProposer = block.coinbase;
    }
    
    
    function finalizeCommit(address[] memory vals, uint256[] memory powers, bool[] memory signed) public {
        _finalizeCommit(vals, powers, signed);
    }
    
    
    function getValidators() public view returns (address[] memory, uint256[] memory) {
        address[] memory vals = new address[](validators.length);
        uint256[] memory powers = new uint256[](validators.length);
        
        for (uint i = 0; i < validators.length; i ++) {
            vals[i] = validators[i].owner;
            powers[i] = validators[i].tokens/(1 * 10 ** 6);
        }
        return (vals, powers);
    }
    
    
    // Mint
    //  --------------------------------------------------
    
    // @dev mints new tokens for the previous block. Returns fee collected
    function mint() public onlyRoot returns(uint256) {
        // recalculate inflation rate
        nextInflationRate();
        // recalculate annual provisions
        nextAnnualProvisions();
        // update fee collected
        _feesCollected = getBlockProvision();
        totalSupply += _feesCollected;
        return _feesCollected;
    }
    
    function nextInflationRate() private {
        uint256 bondedRatio = totalBonded.divTrun(totalSupply);
        uint256 inflationChangeRatePerYear = 0;
        uint256 inflationRateChange = 0;
        if (bondedRatio.divTrun(_params.goalBonded) > oneDec) {
            inflationChangeRatePerYear =  bondedRatio.divTrun(_params.goalBonded).sub(oneDec)
                .mul(_params.inflationRateChange);
            inflationRateChange = inflationRateChange.div(_params.blocksPerYear);
            if (inflationRateChange < inflation) {
                inflation = inflation.sub(inflationRateChange);
            } else {
                inflation = 0;
            }
        } else {
            inflationChangeRatePerYear =  oneDec.sub(bondedRatio.divTrun(_params.goalBonded))
                .mul(_params.inflationRateChange);
            inflationRateChange = inflationRateChange.div(_params.blocksPerYear);
            inflation = inflation.add(inflationRateChange);
        }

        
        if (inflation > _params.inflationMax) {
            inflation = _params.inflationMax;
        }
        if (inflation < _params.inflationMin) {
            inflation = _params.inflationMin;
        }
    }

    function nextAnnualProvisions() private {
        annualProvision = inflation.mulTrun(totalSupply); 
    }

    function getBlockProvision() public view returns(uint256) {
        return annualProvision.div(_params.blocksPerYear);
    }
}