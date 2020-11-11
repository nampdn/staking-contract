pragma solidity 0.5.0;
import "./EnumerableSet.sol";
import "./IValidator.sol";
import "./Safemath.sol";


contract Validator is IValidator {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    uint256 oneDec = 1 * 10**18;
    uint256 powerReduction = 1 * 10**8;

    /*
     * DelStartingInfo represents the starting info for a delegator reward
     * period. It tracks the previous validator period, the delegation's amount of
     * staking token, and the creation height (to check later on if any slashes have
     * occurred)
    */
    struct Delegation {
        uint256 stake; // share delegator's
        uint256 previousPeriod; // previousPeriod uses calculates reward
        uint256 height; // creation height
    }
    
    struct DelegationShare {
        uint256 shares;
        address owner;
    }

    // Validator Commission
    struct Commission {
        // the commission rate charged to delegators, as a fraction
        uint256 rate;
        // maximum commission rate which validator can ever charge, as a fraction
        uint256 maxRate;
        // maximum daily increase of the validator commission, as a fraction
        uint256 maxChangeRate;
    }

    // Unbounding Entry
    struct UBDEntry {
         // KAI to receive at completion
        uint256 amount;
        // height which the unbonding took place
        uint256 blockHeight;
        // unix time for unbonding completion
        uint256 completionTime;
    }

    // validator slash event
    struct SlashEvent {
        uint256 period; // slash validator period 
        uint256 fraction; // fraction slash rate
        uint256 height;
    }

    /*
     * CurrentReward represents current rewards and current period for 
     * a validator kept as a running counter and incremented each block 
     * as long as the validator's tokens remain constant.
    */
    struct CurrentReward {
        uint256 period;
        uint256 reward;
    }

    /* 
     * HistoricalReward represents historical rewards for a validator.
     * Height is implicit within the store key.
     * cumulativeRewardRatio is the sum from the zeroeth period
     * until this period of rewards / tokens, per the spec.
     * The referenceCount indicates the number of objects
     * which might need to reference this historical entry at any point.
     * ReferenceCount = number of outstanding delegations which ended the associated period (and might need to read that record)
     *   + number of slashes which ended the associated period (and might need to
     *  read that record)
     *   + one per validator for the zeroeth period, set on initialization
    */
    struct HistoricalReward {
        uint256 cumulativeRewardRatio;
        uint256 referenceCount;
    }

    // SigningInfo defines a validator's signing info for monitoring their
    // liveness activity.
    struct SigningInfo {
        // height at which validator was first a candidate OR was unjailed
        uint256 startHeight;
        // index offset into signed block bit array
        uint256 indexOffset;
        // whether or not a validator has been tombstoned (killed out of validator set)
        bool tombstoned;
        // missed blocks counter 
        uint256 missedBlockCounter;
        // time for which the validator is jailed until.
        uint256 jailedUntil;
    }
    
    struct MissedBlock {
        mapping(uint256 => bool) items;
    }
    
    struct InforValidator {
        string name;  // validator name
        address payable valAddr; // address of the validator
        address stakingAddr; // staking address
        uint256 tokens; // all token stake
        bool jailed;
        uint256 slashEventCounter;
        uint256 minSelfDelegation;
        uint256 delegationShares; // delegation shares
        uint256 accumulatedCommission;
        uint256 ubdEntryCount; // unbonding delegation entries
    }
    
    uint256 constant public UNBONDING_TiME = 604800; // 7 days
    
    EnumerableSet.AddressSet private delegations; // all delegations
    mapping(address => Delegation) public delegationByAddr; // delegation by address
    mapping(uint256 => HistoricalReward) hRewards;
    mapping(address => DelegationShare) delShare;
    mapping(address => UBDEntry[]) ubdEntries;
    
    InforValidator public inforValidator;
    Commission public commission; // validator commission
    CurrentReward private currentRewards;// current validator rewards
    HistoricalReward private historicalRewards; // historical rewards
    SlashEvent[] private slashEvents; // slash events
    SigningInfo private signingInfo; // signing info
    MissedBlock missedBlock; // missed block

    // called one by the staking at time of deployment  
    function initialize(string calldata _name, address _stakingAddr, address payable _valAddr, uint256 _rate, uint256 _maxRate, 
        uint256 _maxChangeRate, uint256 _minSelfDelegation, uint256 _amount) external {
            
        require(_amount > 0, "invalid delegation amount");
        require(_amount > _minSelfDelegation, "self delegation below minimum");
        require(
            _maxRate <= oneDec,
            "commission max rate cannot be more than 100%"
        );
        require(
            _maxChangeRate <= _maxRate,
            "commission max change rate can not be more than the max rate"
        );
        require(
            _rate <= _maxRate,
            "commission rate cannot be more than the max rate"
        );

        inforValidator.name = _name;
        inforValidator.minSelfDelegation = _minSelfDelegation;
        inforValidator.stakingAddr = _stakingAddr;
        inforValidator.valAddr = _valAddr;
        
        commission = Commission({
            maxRate: _maxRate,
            maxChangeRate: _maxChangeRate,
            rate: _rate
        });
        
        _initializeValidator();
        _delegate(inforValidator.valAddr, _amount);
        signingInfo.startHeight = block.number;
    }
    
    // delegate for this validator
    function delegate() external payable {
        _delegate(msg.sender, msg.value);
    }
    
    // update Commission rate of the validator
    function update(uint256 commissionRate) external {
        require(commissionRate >= 0, "commission rate must greater than 0");
        require(commissionRate <= oneDec, "commission cannot be more than the max rate");
        
        commission.rate = commissionRate;
    }
    
    // _allocateTokens allocate tokens to a particular validator, splitting according to commission
    function allocateToken(uint256 rewards) private {
        uint256 commission = rewards.mulTrun(commission.rate);
        uint256 shared = rewards.sub(commission);
        inforValidator.accumulatedCommission += commission;
        currentRewards.reward += shared;
    }
    
    // validator is jailed when the validator operation misbehave
    function jail() external {
        inforValidator.jailed = true;
    }
    
    // Validator is slashed when the Validator operation misbehave 
    function slash(uint256 infrationHeight, uint256 power, uint256 slashFactor) private {
        require( infrationHeight <= block.number, "cannot slash infrations in the future");
        
        uint256 slashAmount = power.mul(powerReduction).mulTrun(slashFactor);
        if (infrationHeight < block.number) {
            uint256 totalDel = delegations.length();
            for (uint256 i = 0; i < totalDel; i++) {
                address delAddr = delegations.at(i);
                UBDEntry[] storage entries = ubdEntries[delAddr];
                for (uint256 j = 0; j < entries.length; j++) {
                    UBDEntry storage entry = entries[j];
                    if (entry.amount == 0) continue;
                    // if unbonding started before this height, stake did not contribute to infraction;
                    if (entry.blockHeight < infrationHeight) continue;
                    // solhint-disable-next-line not-rely-on-time
                    if (entry.completionTime < block.timestamp) {
                        // unbonding delegation no longer eligible for slashing, skip it
                        continue;
                    }
                    uint256 amountSlashed = entry.amount.mulTrun(slashFactor);
                    entry.amount = entry.amount.sub(amountSlashed);
                    slashAmount = slashAmount.sub(amountSlashed);
                }
            }
        }

        uint256 tokensToBurn = slashAmount;
        if (tokensToBurn > inforValidator.tokens) {
            tokensToBurn = inforValidator.tokens;
        }

        if (inforValidator.tokens > 0) {
            uint256 effectiveFraction = tokensToBurn.divTrun(inforValidator.tokens);
            _updateValidatorSlashFraction(effectiveFraction);
        }

        inforValidator.tokens = inforValidator.tokens.sub(tokensToBurn);
        // removeValidatorRank(valAddr);
    }
    
    function undelegate(address payable _delAddr, uint256 _amount) private {
        require(ubdEntries[_delAddr].length < 7, "too many unbonding delegation entries");
        require(delegations.contains(_delAddr), "delegation not found");
        
        _withdrawRewards(_delAddr);
        DelegationShare storage del = delShare[_delAddr];
        uint256 shares = _shareFromToken(_amount);
        require(del.shares >= shares, "not enough delegation shares");
        del.shares -= shares;
        _initializeDelegation(_delAddr);
        bool isValidatorOperator = inforValidator.valAddr == _delAddr;
        if (
            isValidatorOperator &&
            !inforValidator.jailed &&
            _tokenFromShare(del.shares) < inforValidator.minSelfDelegation
        ) {
            inforValidator.jailed = true; // jail validator
        }

        uint256 amountRemoved = _removeDelShares(shares);
        inforValidator.ubdEntryCount++;
 
        uint256 completionTime = block.timestamp.add(UNBONDING_TiME);
        ubdEntries[_delAddr].push(
            UBDEntry({
                completionTime: completionTime,
                blockHeight: block.number,
                amount: amountRemoved
            })
        );

        // emit Undelegate(valAddr, msg.sender, amount, completionTime);
    }
    
    // withdraw rewards from a delegation
    function withdrawRewards() public {
        require(delegations.contains(msg.sender), "delegator not found");
        _withdrawRewards(msg.sender);
        _initializeDelegation(msg.sender);
    }
    
    // the validator withdraws commission
    function withdrawCommission() public {
        require(msg.sender == inforValidator.valAddr, "validator not found");
        uint256 commission = inforValidator.accumulatedCommission;
        require(commission > 0, "no validator commission to reward");
        inforValidator.valAddr.transfer(commission);
        inforValidator.accumulatedCommission = 0;
        // emit WithdrawCommissionReward(valAddr, commission);
    }
    
    // withdraw token delegator's
    function withdraw() public {
        require(delegations.contains(msg.sender), "delegation not found");
        DelegationShare memory del = delShare[msg.sender];
        UBDEntry[] storage entries = ubdEntries[msg.sender];
        uint256 amount = 0;
        uint256 entryCount = 0;

        for (uint256 i = 0; i < entries.length; i++) {
            // solhint-disable-next-line not-rely-on-time
            if (entries[i].completionTime < block.timestamp) {
                amount = amount.add(entries[i].amount);
                entries[i] = entries[entries.length - 1];
                entries.pop();
                i--;
                entryCount++;
            }
        }
        require(amount > 0, "no unbonding amount to withdraw");
        msg.sender.transfer(amount);
        // totalBonded = totalBonded.sub(amount);

        if (del.shares == 0 && entries.length == 0) {
            _removeDelegation(msg.sender);
        }

        inforValidator.ubdEntryCount = inforValidator.ubdEntryCount.sub(entryCount);
    }
    
    function getCommissionRewards() public view returns(uint256) {
        return inforValidator.accumulatedCommission;
    }
    
    // get rewards from a delegation
    function getDelegationRewards(address _delAddr) public view returns (uint256) {
        require(delegations.contains(_delAddr), "delegation not found");
        DelegationShare memory del = delShare[_delAddr];
        uint256 rewards = _calculateDelegationRewards(
            _delAddr,
            currentRewards.period - 1
        );

        uint256 currentReward = currentRewards.reward;
        if (currentReward > 0) {
            uint256 stake = _tokenFromShare(del.shares);
            rewards += stake.mulTrun(currentReward.divTrun(inforValidator.tokens));
        }
        return rewards;
    }

    
    // remove delegation
    function _removeDelegation(address _delAddr) private {
        delegations.remove(_delAddr);
        delete delegationByAddr[_delAddr];
        delete delegationByAddr[_delAddr];
        // delVals[delAddr].remove(valAddr);
    }
    
    // remove share delegator's
    function _removeDelShares(uint256 _shares) private returns (uint256) {
        uint256 remainingShares = inforValidator.delegationShares;
        uint256 issuedTokens = 0;
        remainingShares = remainingShares.sub(_shares);
        if (remainingShares == 0) {
            issuedTokens = inforValidator.tokens;
            inforValidator.tokens = 0;
        } else {
            issuedTokens = _tokenFromShare(_shares);
            inforValidator.tokens = inforValidator.tokens.sub(issuedTokens);
        }
        inforValidator.delegationShares = remainingShares;
        return issuedTokens;
    }
    
    function _updateValidatorSlashFraction(uint256 _fraction) private {
        uint256 newPeriod = _incrementValidatorPeriod();
        _incrementReferenceCount(inforValidator.valAddr, newPeriod);
        slashEvents[inforValidator.slashEventCounter] = SlashEvent({
            period: newPeriod,
            fraction: _fraction,
            height: block.number
        });
        inforValidator.slashEventCounter++;
    }

    // initialize starting info for a new validator
    function _initializeValidator() private {
        CurrentReward memory currentRewards;
        currentRewards.period = 1;
        currentRewards.reward = 0;
        inforValidator.accumulatedCommission = 0;
    }
    
    function _delegate(address payable _delAddr, uint256 _amount) private {
        // add delegation if not exists;
        if (!delegations.contains(_delAddr)) {
            delegations.add(_delAddr);
            delShare[_delAddr].owner = _delAddr; 
            _beforeDelegationCreated();
        } else {
            _beforeDelegationSharesModified(_delAddr);
        }

        uint256 shared = _addTokenFromDel(_amount);

        // increment stake amount
        DelegationShare storage del = delShare[_delAddr];
        del.shares = del.shares.add(shared);
        _initializeDelegation(_delAddr);
        // emit Delegate(valAddr, delAddr, amount);
    }
    
    function _beforeDelegationCreated() private {
        _incrementValidatorPeriod();
    }
    
    // increment validator period, returning the period just ended
    function _incrementValidatorPeriod() private returns (uint256) {
        CurrentReward memory rewards;
        uint256 previousPeriod = rewards.period.sub(1);
        uint256 current = 0;
        if (rewards.reward > 0) {
            current = rewards.reward.divTrun(inforValidator.tokens);
        }
        uint256 historical = hRewards[previousPeriod]
            .cumulativeRewardRatio;
        _decrementReferenceCount(previousPeriod);

        hRewards[rewards.period].cumulativeRewardRatio = historical.add(current);
        hRewards[rewards.period].referenceCount = 1;
        rewards.period++;
        rewards.reward = 0;
        return previousPeriod.add(1);
    }
    
    // decrement the reference count for a historical rewards value, and delete if zero references remain
    function _decrementReferenceCount(uint256 _period) private {
        hRewards[_period].referenceCount--;
        if (hRewards[_period].referenceCount == 0) {
            delete hRewards[_period];
        }
    }
    
    function _beforeDelegationSharesModified(address payable delAddr) private {
        _withdrawRewards(delAddr);
    }
    
    function _withdrawRewards(address payable _delAddr) private {
        uint256 endingPeriod = _incrementValidatorPeriod();
        uint256 rewards = _calculateDelegationRewards(_delAddr, endingPeriod);
        _decrementReferenceCount(delegationByAddr[_delAddr].previousPeriod);
        
        delete delegationByAddr[_delAddr];
        if (rewards > 0) {
            _delAddr.transfer(rewards);
            // emit WithdrawDelegationRewards(valAddr, delAddr, rewards);
        }
    }
    
    // calculate the total rewards accrued by a delegation
    function _calculateDelegationRewards(
        address _delAddr,
        uint256 _endingPeriod
    ) private view returns (uint256) {
        // fetch starting info for delegation
        Delegation memory delegationInfo = delegationByAddr[_delAddr];
        uint256 rewards = 0;
        uint256 slashEventCounter = slashEvents.length;
        for (uint256 i = 0; i < slashEventCounter; i++) {
            SlashEvent memory slashEvent = slashEvents[i];
            if (
                slashEvent.height > delegationInfo.height &&
                slashEvent.height < block.number
            ) {
                uint256 _endingPeriod = slashEvent.period;
                if (_endingPeriod > delegationInfo.previousPeriod) {
                    rewards += _calculateDelegationRewardsBetween(
                        delegationInfo.previousPeriod,
                        slashEvent.period,
                        delegationInfo.stake
                    );
                    delegationInfo.stake = delegationInfo.stake.mulTrun(
                        oneDec.sub(slashEvent.fraction)
                    );
                    delegationInfo.previousPeriod = _endingPeriod;
                }
            }
        }
        rewards += _calculateDelegationRewardsBetween(
            delegationInfo.previousPeriod,
            _endingPeriod,
            delegationInfo.stake
        );
        return rewards;
    }
    
    // calculate the rewards accrued by a delegation between two periods
    function _calculateDelegationRewardsBetween(
        uint256 _startingPeriod,
        uint256 _endingPeriod,
        uint256 _stake
    ) private view returns (uint256) {
        HistoricalReward memory starting = hRewards[_startingPeriod];
        HistoricalReward storage ending = hRewards[_endingPeriod];
        uint256 difference = ending.cumulativeRewardRatio.sub(
            starting.cumulativeRewardRatio
        );
        return _stake.mulTrun(difference); // return staking * (ending - starting)
    }
    
    function _addToken(uint256 _amount) private returns(uint256) {
        uint256 issuedShares = 0;
        if (inforValidator.tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(_amount);
        }
        inforValidator.tokens = inforValidator.tokens.add(_amount);
        inforValidator.delegationShares = inforValidator.delegationShares.add(issuedShares);
        return inforValidator.delegationShares;
    }
    
    function _shareFromToken(uint256 _amount) private view returns(uint256) {
        return inforValidator.delegationShares.
        mul(_amount).div(inforValidator.tokens);
    }
    
    // calculate share delegator's
    function _addTokenFromDel(uint256 _amount) private returns (uint256) {
        uint256 issuedShares = 0;
        if (inforValidator.tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(_amount);
        }
        inforValidator.tokens = inforValidator.tokens.add(_amount);
        inforValidator.delegationShares = inforValidator.delegationShares.add(issuedShares);
        return issuedShares;
    }
    
    // initialize starting info for a new delegation
    function _initializeDelegation(address _delAddr) private {
        DelegationShare storage del = delShare[_delAddr];
        uint256 previousPeriod = currentRewards.period - 1;
        _incrementReferenceCount(inforValidator.valAddr, previousPeriod);
        delegationByAddr[_delAddr].height = block.number;
        delegationByAddr[_delAddr].previousPeriod = previousPeriod;
        uint256 stake = _tokenFromShare(del.shares);
        delegationByAddr[_delAddr].stake = stake;
    }
    
    // increment the reference count for a historical rewards value
    function _incrementReferenceCount(address valAddr, uint256 _period) private {
        hRewards[_period].referenceCount++;
    }
    
    // token worth of provided delegator shares
    function _tokenFromShare(uint256 _shares) private view returns (uint256) {
        return _shares.mul(inforValidator.tokens).div(inforValidator.delegationShares);
    }
}