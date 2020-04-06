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
    mapping(address => mapping(uint256 => ValidatorHistoricalRewards)) validatorHistoricalRewards;
    mapping(address => bool[]) validatorMissedBlockBitArray;
    mapping(address => ValidatorSigningInfo) validatorSigningInfos;
    mapping(address => uint256) validatorAccumulatedCommission;
    mapping(address => Delegation[]) delegations;
    mapping(address => uint) validatorsIndex;
    
    Params _params;
    address _previousProposer;
    
    function createValidator() public payable {
        _createValidator(msg.sender, msg.value);
    }
    
    function _createValidator(address payable valAddr, uint256 amount) private{
        require(validatorsIndex[valAddr] == 0, "validator owner exists");
        require(amount > 0, "invalid delegation amount");
        ValidatorCommission memory commission = ValidatorCommission({rate: 0});
        validators.push(Validator({owner: valAddr, tokens: 0, delegationShares: 1, jailed: false, commission: commission}));
        validatorsIndex[valAddr] = validators.length;
        _delegate(valAddr, valAddr, amount);
        _afterValidatorCreated(valAddr);
    }
    
    function _afterValidatorCreated(address valAddr) private {
        _initializeValidator(valAddr);
    }
    
    function _afterDelegationModified(address valAddr, address delAddr) private {
        _initializeDelegation(valAddr, delAddr);
    }
    
    
    function _delegate(address payable delAddr, address valAddr, uint256 amount) private {
        Validator storage val = validators[validatorsIndex[valAddr]-1];
        uint delIndex = delegationsIndex[valAddr][delAddr];
        
        // add delegation if not exists;
        if (delIndex == 0) {
            delegations[valAddr].push(Delegation({
                owner: delAddr,
                shares: 0
            }));
            
            delegationsIndex[valAddr][delAddr] = delegations[valAddr].length;
            _beforeDelegationCreated(valAddr);
        } else {
            _beforeDelegationSharesModified(valAddr, delAddr);
        }
        
        uint256 shared = val.delegationShares.mul(amount).div(val.tokens);
        
        // increment stake amount
        Delegation storage del = delegations[valAddr][delIndex -1];
        del.shares = shared;
        val.tokens += amount;
        val.delegationShares += shared;
        _afterDelegationModified(valAddr, delAddr);
        
    }
    
    function delegate(address valAddr) public payable {
        require(validators[validatorsIndex[valAddr]-1].owner != address(0x0), "validator does not exists");
        require(msg.value > 0, "invalid delegation amount");
        _delegate(msg.sender, valAddr, msg.value);
    }
    
    function _undelegate(address valAddr, address delAddr, uint256 amount) private {
        require(unbondingEntries[valAddr][delAddr].length >= 7, "too many unbonding delegation entries");
        uint delegationIndex = delegationsIndex[valAddr][delAddr];
        require(delegationIndex > 0, "delegation not found");
        Validator storage val = validators[validatorsIndex[valAddr]-1];
        Delegation storage del = delegations[valAddr][delegationIndex -1];
        uint256 shares = val.delegationShares.mul(amount).div(val.tokens);
        require(del.shares > shares, "invalid undelegate amount");
        uint256 token = shares.mul(val.tokens).div(val.delegationShares);
        val.delegationShares -= shares;
        val.tokens -= token;
        del.shares -= shares;
        
        unbondingEntries[valAddr][delAddr].push(UBDEntry({
            completionTime: block.timestamp.add(_params.unboudingTime),
            blockHeight: block.number,
            amount: token
        }));
        
        if (del.shares == 0) {
            _removeDelegation(valAddr, delAddr);
        }
        
        if (val.delegationShares == 0) {
            _removeValidator(valAddr);
        }
        
    }
    
    function undelegate(address valAddr, uint256 amount) public {
        _undelegate(msg.sender, valAddr, amount);
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
    }
    
    function _removeDelegation(address valAddr, address delAddr) private {
        uint delegationIndex = delegationsIndex[valAddr][delAddr];
        uint lastDelegationIndex = delegations[valAddr].length;
        Delegation memory lastDelegation = delegations[valAddr][lastDelegationIndex -1];
        delegations[valAddr][delegationIndex-1] = lastDelegation;
        delegations[valAddr].pop();
        delete delegatorStartingInfo[valAddr][delAddr];
    }
    
    function _removeValidator(address valAddr) private{
        delete validatorSlashEvents[valAddr];
        delete validatorAccumulatedCommission[valAddr];
        for (uint i = 0; i < validatorCurrentRewards[valAddr].period; i ++) {
            delete validatorHistoricalRewards[valAddr][i];
        }
        delete validatorCurrentRewards[valAddr];
        
        uint valIndex = validatorsIndex[valAddr];
        uint lastIndex = validators.length;
        Validator memory lastVal = validators[lastIndex -1];
        validators[valIndex-1] = lastVal;
        validators.pop();
        validatorsIndex[lastVal.owner] = valIndex;
        delete validatorsIndex[valAddr];
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
        Validator memory val = validators[validatorsIndex[valAddr]-1];
        uint256 previousPeriod = validatorCurrentRewards[valAddr].period +1;
        _incrementReferenceCount(valAddr, previousPeriod);
        delegatorStartingInfo[valAddr][delAddr].height = block.number;
        delegatorStartingInfo[valAddr][delAddr].previousPeriod = previousPeriod;
        uint256 stake = delegations[valAddr][delegationIndex].shares.div(val.delegationShares);
        delegatorStartingInfo[valAddr][delAddr].stake = stake;
    }
    
    function _initializeValidator(address valAddr) private {
        validatorHistoricalRewards[valAddr][0].reference_count = 1;
        validatorCurrentRewards[valAddr].period = 1;
        validatorCurrentRewards[valAddr].reward = 0;
        validatorMissedBlockBitArray[valAddr] = new bool[](_params.signedBlockWindown);
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
        _withdrawRewards(valAddr, msg.sender);
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
                validatorMissedBlockBitArray[valAddr] = new bool[](_params.signedBlockWindown);
            }
        }
        
    }
    
    function _allocateTokens(uint256 sumPreviousPrecommitPower, uint256 totalPreviousVotingPower, 
        address previousProposer, address[] memory vals, uint256[] memory powers) private{
        uint256 feesCollected = 100;
        uint256 previousFractionVotes = sumPreviousPrecommitPower.div(totalPreviousVotingPower);
        uint256 proposerMultiplier = _params.baseProposerReward.add(_params.baseProposerReward.mul(previousFractionVotes));
        uint256 proposerReward = feesCollected.mul(proposerMultiplier);
        _allocateTokensToValidator(previousProposer, proposerReward);
        feesCollected -= proposerReward;
        
        uint256 voteMultiplier = 1 - proposerMultiplier;
        for (uint i = 0; i < vals.length; i ++) {
            uint256 powerFraction = powers[i].div(totalPreviousVotingPower);
            uint256 rewards = feesCollected.mul(voteMultiplier).mul(powerFraction);
            _allocateTokensToValidator(vals[0], rewards);
            feesCollected -= rewards;
        }
    }
    
    function _allocateTokensToValidator(address valAddr, uint256 rewards) private{
        uint256 commission = rewards.mul(validators[validatorsIndex[valAddr]-1].commission.rate);
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
}