pragma solidity >=0.4.21 <0.7.0;
import {SafeMath} from "./Safemath.sol";



contract StakingNew {
    using SafeMath for uint256;

    struct Delegation {
        uint256 shares;
        address owner;
    }
    
    struct UBDEntry {
        uint256 amount;
        uint256 blockHeight;
        uint256 completionTime;
    }
    
    struct Validator {
        address owner;
        uint256 tokens;
        uint256 delegationShares;
        Delegation[] delegations;
        bool jailed;
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
    
    
    mapping(address => Validator) validators;
    mapping(address => mapping(address => uint)) delegationsIndex;
    mapping(address => mapping(address => UBDEntry[])) unbondingEntries;
    mapping(address => mapping(address => DelegatorStartingInfo)) delegatorStartingInfo;
    mapping(address => ValidatorSlashEvent[]) validatorSlashEvents;
    mapping(address => ValidatorCurrentReward) validatorCurrentRewards;
    mapping(address => mapping(uint256 => ValidatorHistoricalRewards)) validatorHistoricalRewards;
    mapping(address => bool[]) validatorMissedBlockBitArray;
    mapping(address => ValidatorSigningInfo) validatorSigningInfos;
    Params _params;
    
    
    function _delegate(address delAddr, address valAddr, uint256 amount) private {
        Validator storage val = validators[valAddr];
        uint delIndex = delegationsIndex[valAddr][delAddr];
        
        // add delegation if not exists;
        if (delIndex == 0) {
            val.delegations.push(Delegation({
                owner: delAddr,
                shares: 0
            }));
            
            delegationsIndex[valAddr][delAddr] = val.delegations.length;
        }
        
        uint256 shared = val.delegationShares.mul(amount).div(val.tokens);
        
        // increment stake amount
        Delegation storage del = val.delegations[delIndex -1];
        del.shares = shared;
        val.tokens += amount;
        val.delegationShares += shared;
        
    }
    
    function delegate(address valAddr) public payable {
        require(validators[valAddr].owner != address(0x0), "validator does not exists");
        require(msg.value > 0, "invalid delegation amount");
        _delegate(msg.sender, valAddr, msg.value);
    }
    
    function _undelegate(address valAddr, address delAddr, uint256 amount) private {
        uint delegationIndex = delegationsIndex[valAddr][delAddr];
        require(delegationIndex > 0, "delegation not found");
        Validator storage val = validators[valAddr];
        Delegation storage del = val.delegations[delegationIndex -1];
        uint256 shares = val.delegationShares.mul(amount).div(val.tokens);
        require(del.shares > shares, "invalid undelegate amount");
        uint256 token = shares.mul(val.tokens).div(val.delegationShares);
        val.delegationShares -= shares;
        val.tokens -= token;
        del.shares -= shares;
        
        unbondingEntries[valAddr][delAddr].push(UBDEntry({
            completionTime: 1,
            blockHeight: block.number,
            amount: token
        }));
        
    }
    
    function undelegate(address valAddr, uint256 amount) public {
        _undelegate(msg.sender, valAddr, amount);
    }
    
    function _jail(address valAddr) private {
        validators[valAddr].jailed = true;
    }
    
    
    function _slash(address valAddr, uint256 infrationHeight, uint256 power, uint256 slashFactor) private {
        require(infrationHeight <= block.number, "");
        Validator storage val = validators[valAddr];
        uint256 slashAmount = power.mul(slashFactor);
        if (infrationHeight < block.number) {
            for (uint i = 0; i < val.delegations.length; i ++) {
                UBDEntry[] storage entries = unbondingEntries[valAddr][val.delegations[i].owner];
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
    }
    
    
    function _withdrawl(address valAddr, address payable delAddr) private returns (uint256){
        UBDEntry[] storage entries= unbondingEntries[valAddr][delAddr];
        uint256 amount = 0;
        for (uint i = 0; i < entries.length; i ++) {
            if (entries[i].completionTime < block.timestamp) {
                amount += entries[i].amount;
                entries[i] = entries[entries.length - 1];
                entries.pop();
            }
        }
        delAddr.transfer(amount);
        return amount;
    }
    
    function withdrawl(address valAddr) public {
        _withdrawl(valAddr, msg.sender);
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
        Validator memory val = validators[valAddr];
        ValidatorCurrentReward storage rewards = validatorCurrentRewards[valAddr];
        uint256 current = rewards.reward.div(val.tokens);
        uint256 historical = validatorHistoricalRewards[valAddr][rewards.period - 1].cumulativeRewardRatio;
        _decrementReferenceCount(valAddr, rewards.period);
        validatorHistoricalRewards[valAddr][rewards.period].cumulativeRewardRatio = historical + current;
        rewards.period++;
        rewards.reward = 0;
        return rewards.period;
        
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
        Validator memory val = validators[valAddr];
        uint256 previousPeriod = validatorCurrentRewards[valAddr].period +1;
        _incrementReferenceCount(valAddr, previousPeriod);
        delegatorStartingInfo[valAddr][delAddr].height = block.number;
        delegatorStartingInfo[valAddr][delAddr].previousPeriod = previousPeriod;
        uint256 stake = val.delegations[delegationIndex].shares.div(val.delegationShares);
        delegatorStartingInfo[valAddr][delAddr].stake = stake;
    }
    
    function _initializeValidator(address valAddr) private {
        validatorHistoricalRewards[valAddr][0].reference_count = 1;
        validatorCurrentRewards[valAddr].period = 1;
        validatorCurrentRewards[valAddr].reward = 0;
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
        _withdrawRewards(valAddr, msg.sender);
    }
    
    
    function _doubleSign(address valAddr, uint256 votingPower, uint256 distributionHeight) private {
        _slash(valAddr, distributionHeight, votingPower, 0); 
    }
    
    function doubleSign(address valAddr, uint256 votingPower, uint256 distributionHeight) public {
        _doubleSign(valAddr, votingPower, distributionHeight);
    }
    
    function _validateSignature(address valAddr, uint256 votingPower, bool signed) private{
        Validator storage val = validators[valAddr];
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
                _slash(valAddr, block.number, votingPower, 1);
                _jail(valAddr);
                signInfo.jailedUntil = block.timestamp.add(_params.slashFractionDowntime);
                signInfo.missedBlockCounter = 0;
                signInfo.indexOffset = 0;
                validatorMissedBlockBitArray[valAddr] = new bool[](_params.signedBlockWindown);
            }
        }
        
    }
}