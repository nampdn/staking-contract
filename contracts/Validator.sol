pragma solidity 0.5.0;
import "./EnumerableSet.sol";
import "./IValidator.sol";
import "./Safemath.sol";


contract Validator is IValidator {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    uint256 oneDec = 1 * 10**18;

    // Delegation
    struct Delegation {
        uint256 stake;
        uint256 previousPeriod;
        uint256 height;
    }
    
    struct DelegationShare {
        uint256 shares;
        address owner;
    }

    // Validator Commission
    struct Commission {
        uint256 rate;
        uint256 maxRate;
        uint256 maxChangeRate;
    }

    // Unbounding Entry
    struct UBDEntry {
        uint256 amount;
        uint256 blockHeight;
        uint256 completionTime;
    }

    // validator slash event
    struct SlashEvent {
        uint256 period;
        uint256 fraction;
        uint256 height;
    }

    // Validator current rewards
    struct CurrentReward {
        uint256 period;
        uint256 reward;
    }

    // Validator Historical Reward
    struct HistoricalReward {
        uint256 cumulativeRewardRatio;
        uint256 referenceCount;
    }

    struct SigningInfo {
        uint256 startHeight;
        uint256 indexOffset;
        bool tombstoned;
        uint256 missedBlockCounter;
        uint256 jailedUntil;
    }
    
    struct MissedBlock {
        mapping(uint256 => bool) items;
    }

    string public name; // validator name
    address payable public valAddr;
    EnumerableSet.AddressSet private delegations; // all delegations
    mapping(address => Delegation) public delegationByAddr; // delegation by address
    mapping(uint256 => HistoricalReward) hRewards;
    mapping(address => DelegationShare) delShare;
    Commission public commission; // validator commission
    CurrentReward private currentRewwards;// current validator rewards
    HistoricalReward private historicalRewards; // historical rewards
    SlashEvent[] private slashEvents; // slash events
    SigningInfo private signingInfo; // signing info
    MissedBlock missedBlock; // missed block
    address public stakingAddr; // staking address
    uint256 public minSelfDelegation; 
    uint256 public tokens; // all token stake
    uint256 public delegationShares; // delegation shares
    uint256 public accumulatedCommission;

    // called one by the staking at time of deployment  
    function initialize(string calldata _name, address _stakingAddr, address payable _valAddr, uint256 _rate, uint256 _maxRate, 
        uint256 _maxChangeRate, uint256 _minSelfDelegation, uint256 _amount) external {
            
        require(_amount > 0, "invalid delegation amount");
        require(_amount > minSelfDelegation, "self delegation below minimum");
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

        name = _name;
        minSelfDelegation = _minSelfDelegation;
        stakingAddr = _stakingAddr;
        valAddr = _valAddr;
        
        commission = Commission({
            maxRate: _maxRate,
            maxChangeRate: _maxChangeRate,
            rate: _rate
        });
        
        _initializeValidator();
        _delegate(valAddr, _amount);
        // valSigningInfos[valAddr].startHeight = block.number;
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
    function allocateToken(uint256 rewards)
        private
    {
        uint256 commission = rewards.mulTrun(commission.rate);
        uint256 shared = rewards.sub(commission);
        accumulatedCommission += commission;
        currentRewwards.reward += shared;
    }
    
    // initialize starting info for a new validator
    function _initializeValidator() private {
        CurrentReward memory currentRewwards;
        currentRewwards.period = 1;
        currentRewwards.reward = 0;
        accumulatedCommission = 0;
    }
    
    function _delegate(address payable _delAddr, uint256 _amount)
        private
    {
        // add delegation if not exists;
        if (!delegations.contains(_delAddr)) {
            delegations.add(_delAddr);
            delShare[_delAddr].owner = _delAddr;
            _beforeDelegationCreated();
        } else {
            _beforeDelegationSharesModified(_delAddr);
        }

        uint256 shared = _addTokenFromDel(_amount);

        // totalBonded = totalBonded.add(_amount);

        // increment stake amount
        DelegationShare storage del = delShare[_delAddr];
        del.shares = del.shares.add(shared);
        _afterDelegationModified(_delAddr);
        // addValidatorRank(valAddr);
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
            current = rewards.reward.divTrun(tokens);
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
    function _decrementReferenceCount(uint256 period) private {
        hRewards[period].referenceCount--;
        if (hRewards[period].referenceCount == 0) {
            delete hRewards[period];
        }
    }
    
    function _beforeDelegationSharesModified(address payable delAddr) private {
        _withdrawRewards(delAddr);
    }
    
    function _withdrawRewards(address payable delAddr) private {
        uint256 endingPeriod = _incrementValidatorPeriod();
        uint256 rewards = _calculateDelegationRewards(delAddr, endingPeriod);
        _decrementReferenceCount(delegationByAddr[delAddr].previousPeriod);
        
        delete delegationByAddr[delAddr];
        if (rewards > 0) {
            delAddr.transfer(rewards);
            // emit WithdrawDelegationRewards(valAddr, delAddr, rewards);
        }
    }
    
    // calculate the total rewards accrued by a delegation
    function _calculateDelegationRewards(
        address delAddr,
        uint256 endingPeriod
    ) private view returns (uint256) {
        // fetch starting info for delegation
        Delegation memory delegationInfo = delegationByAddr[delAddr];
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
            endingPeriod,
            delegationInfo.stake
        );
        return rewards;
    }
    
    // calculate the rewards accrued by a delegation between two periods
    function _calculateDelegationRewardsBetween(
        uint256 startingPeriod,
        uint256 endingPeriod,
        uint256 stake
    ) private view returns (uint256) {
        HistoricalReward memory starting = hRewards[startingPeriod];
        HistoricalReward storage ending = hRewards[endingPeriod];
        uint256 difference = ending.cumulativeRewardRatio.sub(
            starting.cumulativeRewardRatio
        );
        return stake.mulTrun(difference); // return staking * (ending - starting)
    }
    
    function _addToken(uint256 _amount) private returns(uint256) {
        uint256 issuedShares = 0;
        if (tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(_amount);
        }
        tokens = tokens.add(_amount);
        delegationShares = delegationShares.add(issuedShares);
        return delegationShares;
    }
    
    function _shareFromToken(uint256 _amount) private view returns(uint256){
        return delegationShares.mul(_amount).div(tokens);
    }
    
    // calculate share delegator's
    function _addTokenFromDel(uint256 _amount)
        private
        returns (uint256)
    {
        uint256 issuedShares = 0;
        if (tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(_amount);
        }
        tokens = tokens.add(_amount);
        delegationShares = delegationShares.add(issuedShares);
        return issuedShares;
    }
    
    function _afterDelegationModified(address _delAddr) private {
        _initializeDelegation(_delAddr);
    }
    
    // initialize starting info for a new delegation
    function _initializeDelegation(address _delAddr) private {
        DelegationShare storage del = delShare[_delAddr];
        uint256 previousPeriod = currentRewwards.period - 1;
        _incrementReferenceCount(valAddr, previousPeriod);
        delegationByAddr[_delAddr].height = block.number;
        delegationByAddr[_delAddr].previousPeriod = previousPeriod;
        uint256 stake = _tokenFromShare(valAddr, del.shares);
        delegationByAddr[_delAddr].stake = stake;
    }
    
    // increment the reference count for a historical rewards value
    function _incrementReferenceCount(address valAddr, uint256 _period) private {
        hRewards[_period].referenceCount++;
    }
    
    // token worth of provided delegator shares
    function _tokenFromShare(address valAddr, uint256 _shares) private view returns (uint256) {
        return _shares.mul(tokens).div(delegationShares);
    }
    




    // function _delegate(address delAddr, uint256 amount) private{
    //     uint256 shared = _addTokenFromDel(valAddr, amount);
    //     // increment stake amount
    //     Delegation storage del = delegationByAddr[delAddr];
    //     del.shares = shared
    // }


    // // undelegate
    // function undelegate(uint64 amount) external {
        
    // }
}