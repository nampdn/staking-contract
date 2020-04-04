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
    
    mapping(address => Validator) validators;
    mapping(address => mapping(address => uint)) delegationsIndex;
    mapping(address => mapping(address => UBDEntry[])) unbondingEntries;
    mapping(address => mapping(address => DelegatorStartingInfo)) delegatorStartingInfo;
    mapping(address => ValidatorSlashEvent[]) validatorSlashEvents;
    mapping(address => ValidatorCurrentReward) validatorCurrentRewards;
    mapping(address => mapping(uint256 => ValidatorHistoricalRewards)) validatorHistoricalRewards;
    
    
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
    
    
    function _withdrawl(address valAddr, address delAddr, uint256) private returns (uint256){
        UBDEntry[] storage entries= unbondingEntries[valAddr][delAddr];
        uint256 amount = 0;
        for (uint i = 0; i < entries.length; i ++) {
            if (entries[i].completionTime < block.timestamp) {
                amount += entries[i].amount;
                entries[i] = entries[entries.length - 1];
                entries.pop();
            }
        }
        return amount;
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
    
}