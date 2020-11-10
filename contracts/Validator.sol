pragma solidity >=0.5.0;
import "./EnumerableSet.sol";
import "./IValidator.sol";


contract Validator is IValidator {
    using EnumerableSet for EnumerableSet.AddressSet;
    uint256 oneDec = 1 * 10**18;

    // Delegation
    struct Delegation {
        uint256 stake;
        uint256 previousPeriod;
        uint256 height;
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


    string name; // validator name
    address payable public valAddr;
    EnumerableSet.AddressSet private delegations; // all delegations
    EnumerableSet.AddressSet private delValidator;
    mapping(address => Delegation) public delegationByAddr; // delegation by address
    mapping(uint256 => HistoricalReward) hRewards;
    Commission public commission; // validator commission
    CurrentReward private currentRewwards;// current validator rewards
    HistoricalReward private historicalRewards; // historical rewards
    SlashEvent[] private slashEvents; // slash events
    SigningInfo private signingInfo; // signing info
    MissedBlock missedBlock; // missed block
    address public stakingAddr; // staking address
    uint256 public minSelfDelegation; 
    uint64 public tokens; // all token stake
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
        
         _afterValidatorCreated(valAddr);
        _delegate(_valAddr, _valAddr, _amount);
        // valSigningInfos[valAddr].startHeight = block.number;
    }
    
    function _afterValidatorCreated(address _valAddr) private {
        _initializeValidator(_valAddr);
    }
    
     // initialize starting info for a new validator
    function _initializeValidator() private {
        CurrentReward memory currentRewwards;
        currentRewwards.period = 1;
        currentRewwards.reward = 0;
        accumulatedCommission = 0;
    }
    
    function _delegate(address payable _delAddr, address _valAddr, uint256 _amount)
        private
    {
        // add delegation if not exists;
        if (!delegations.contains(_delAddr)) {
            delegations.add(_delAddr);
            delValidator[_delAddr].add(_valAddr);
            delegationByAddr[_valAddr][_delAddr].owner = _delAddr;
            _beforeDelegationCreated(_valAddr);
        } else {
            _beforeDelegationSharesModified(_valAddr, _delAddr);
        }

        uint256 shared = _addTokenFromDel(_valAddr, _amount);

        // totalBonded = totalBonded.add(_amount);

        // increment stake amount
        Delegation storage del = delByAddr[_valAddr][_delAddr];
        del.shares = del.shares.add(shared);
        _afterDelegationModified(_valAddr, _delAddr);
        addValidatorRank(_valAddr);
        // emit Delegate(valAddr, delAddr, amount);
    }
    
    function _beforeDelegationCreated(address valAddr) private {
        _incrementValidatorPeriod(valAddr);
    }
    
    // increment validator period, returning the period just ended
    function _incrementValidatorPeriod(address valAddr)
        private
        returns (uint256)
    {
        CurrentReward storage rewards;
        uint256 previousPeriod = rewards.period.sub(1);
        uint256 current = 0;
        if (rewards.reward > 0) {
            current = rewards.reward.divTrun(tokens);
        }
        uint256 historical = hRewards[previousPeriod]
            .cumulativeRewardRatio;
        _decrementReferenceCount(valAddr, previousPeriod);

        hRewards[rewards.period].cumulativeRewardRatio = historical.add(current);
        hRewards[rewards.period].reference_count = 1;
        rewards.period++;
        rewards.reward = 0;
        return previousPeriod.add(1);
    }
    
    // decrement the reference count for a historical rewards value, and delete if zero references remain
    function _decrementReferenceCount(address valAddr, uint256 period) private {
        hRewards[period].reference_count--;
        if (hRewards[period].reference_count == 0) {
            delete hRewards[period];
        }
    }
    
    
    function _beforeDelegationSharesModified(
        address valAddr,
        address payable delAddr
    ) private {
        _withdrawRewards(valAddr, delAddr);
    }
    
    function _withdrawRewards(address valAddr, address payable delAddr) private {
        uint256 endingPeriod = _incrementValidatorPeriod(valAddr);
        uint256 rewards = _calculateDelegationRewards(
            valAddr,
            delAddr,
            endingPeriod
        );
        _decrementReferenceCount(
            valAddr,
            delegationByAddr[delAddr].previousPeriod
        );
        
        delete delegationByAddr[delAddr];
        if (rewards > 0) {
            delAddr.transfer(rewards);
            // emit WithdrawDelegationRewards(valAddr, delAddr, rewards);
        }
    }
    
        // calculate the total rewards accrued by a delegation
    function _calculateDelegationRewards(
        address valAddr,
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
                uint256 _endingPeriod = slashEvent.validatorPeriod;
                if (_endingPeriod > delegationInfo.previousPeriod) {
                    rewards += _calculateDelegationRewardsBetween(
                        valAddr,
                        delegationInfo.previousPeriod,
                        slashEvent.validatorPeriod,
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
            valAddr,
            delegationInfo.previousPeriod,
            endingPeriod,
            delegationInfo.stake
        );
        return rewards;
    }
    
    // calculate the rewards accrued by a delegation between two periods
    function _calculateDelegationRewardsBetween(
        address valAddr,
        uint256 startingPeriod,
        uint256 endingPeriod,
        uint256 stake
    ) private view returns (uint256) {
        CurrentReward memory starting = hRewards[startingPeriod];
        CurrentReward memory ending = hRewards[endingPeriod];
        uint256 difference = ending.cumulativeRewardRatio.sub(
            starting.cumulativeRewardRatio
        );
        return stake.mulTrun(difference); // return staking * (ending - starting)
    }
    
    function _addToken(uint64 amount) private returns(uint256) {
        uint256 issuedShares = 0;
        if (tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(valAddr, amount);
        }
        tokens = tokens.add(amount);
        delegationShares = delegationShares.add(issuedShares);
        return delegationShares;
    }
    
    function _shareFromToken(uint64 amount) private view returns(uint256){
        return delegationShares.mul(amount).div(tokens);
    }


    // // delegate for this validator
    // function delegate() external payable {
    //     _delegate(msg.sender, msg.value)
    // }

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