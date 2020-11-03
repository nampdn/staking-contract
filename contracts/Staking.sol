pragma solidity ^0.6.0;
import {SafeMath} from "./Safemath.sol";
import {IStaking} from "./IStaking.sol";
import "./EnumerableSet.sol";
import {Ownable} from "./Ownable.sol";

contract Staking is IStaking, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 oneDec = 1 * 10**18;
    uint256 powerReduction = 1 * 10**8;

    struct Delegation {
        uint256 shares;
        address owner;
    }

    struct UBDEntry {
        // KAI to receive at completion
        uint256 amount;
         // height which the unbonding took place
        uint256 blockHeight;
        // unix time for unbonding completion
        uint256 completionTime;
    }

    struct Commission {
        // the commission rate charged to delegators, as a fraction
        uint256 rate; 
        // maximum commission rate which validator can ever charge, as a fraction
        uint256 maxRate;
        // maximum daily increase of the validator commission, as a fraction
        uint256 maxChangeRate;
    }

    struct Validator {
        address owner; // address of the Validator
        uint256 tokens; // delegated token
        uint256 delegationShares; // total share issued to Validator's delegator
        bool jailed; 
        Commission commission; // commission paramater
        uint256 minSelfDelegation; // Validator's self decalared  
        uint256 updateTime; // the last time the validator was changed
        uint256 ubdEntryCount; // unbonding delegation entries
        mapping(uint256 => ValHRewards) hRewards;
        mapping(uint256 => ValSlashEvent) slashEvents;
        uint256 slashEventCounter;
        MissedBlock missedBlock;
    }

    /*
    DelStartingInfo represents the starting info for a delegator reward
    period. It tracks the previous validator period, the delegation's amount of
    staking token, and the creation height (to check later on if any slashes have
    occurred)
    */
    struct DelStartingInfo {  
        uint256 stake; // share delegator's
        uint256 previousPeriod; // previousPeriod uses calculates reward
        uint256 height; // creation heigh
    }

    struct ValSlashEvent {
        uint256 validatorPeriod; // slash validator period 
        uint256 fraction; // fraction slash rate
        uint256 height; 
    }

    /*
    ValCurrentReward represents current rewards and current period for 
    a validator kept as a running counter and incremented each block 
    as long as the validator's tokens remain constant.
    */
    struct ValCurrentReward {
        uint256 period;
        uint256 reward;
    }

    /* 
    ValHRewards represents historical rewards for a validator.
    Height is implicit within the store key.
    cumulativeRewardRatio is the sum from the zeroeth period
    until this period of rewards / tokens, per the spec.
    The reference_count indicates the number of objects
    which might need to reference this historical entry at any point.
    ReferenceCount = number of outstanding delegations which ended the associated period (and might need to read that record)
        + number of slashes which ended the associated period (and might need to
    read that record)
        + one per validator for the zeroeth period, set on initialization
    */
    struct ValHRewards {
        uint256 cumulativeRewardRatio; 
        uint256 reference_count;
    }

    // ValSigningInfo defines a validator's signing info for monitoring their
    // liveness activity.
    struct ValSigningInfo {
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

    struct Params {
        uint256 baseProposerReward; // the current distribution base proposer rate
        uint256 bonusProposerReward; //  the current distribution bonus proposer reward rate
        uint256 maxValidators;  // maximum number of Validators
        uint256 downtimeJailDuration; // jail time
        uint256 slashFractionDowntime; // percentage slash when the validator downtime
        uint256 unbondingTime; // unbonding time
        uint256 slashFractionDoubleSign; // percentage slash when the validator double signs 
        uint256 signedBlockWindow; // sliding window for downtime slashing
        uint256 minSignedPerWindow; // minimum blocks signed per window
        // mint params
        uint256 inflationRateChange;  // maximum annual change in inflation rate
        uint256 goalBonded; // goal of percent bonded KAI
        uint256 blocksPerYear; // expected blocks per year
        uint256 inflationMax;  // maximum inflation rate
        uint256 inflationMin; // minimum inflation rate
    }

    mapping(address => Validator) valByAddr;
    EnumerableSet.AddressSet vals;
    mapping(address => mapping(address => UBDEntry[])) public ubdEntries;
    mapping(address => mapping(address => DelStartingInfo)) public delStartingInfo;
    mapping(address => ValCurrentReward) public valCurrentRewards;
    mapping(address => ValSigningInfo) public valSigningInfos;
    mapping(address => uint256) public valAccumulatedCommission;
    mapping(address => mapping(address => Delegation)) public delByAddr;
    mapping(address => EnumerableSet.AddressSet) delVals;
    mapping(address => EnumerableSet.AddressSet) dels;

    // sort
    address[] public valRanks;
    mapping(address => uint256) valRankIndexes;

    struct MissedBlock {
        mapping(uint256 => bool) items;
    }

    bool _needSort;

    // supply
    uint256 public totalSupply = 5000000000 * 10**18;
    uint256 public totalBonded;
    uint256 public inflation;
    uint256 public annualProvision;
    uint256 _feesCollected;
    // mint

    Params _params;
    address _previousProposer;

    constructor() public {
        _params = Params({
            maxValidators: 100,
            downtimeJailDuration: 600,
            baseProposerReward: 1 * 10**16,
            bonusProposerReward: 4 * 10**16,
            slashFractionDowntime: 1 * 10**14,
            unbondingTime: 1814400,
            slashFractionDoubleSign: 5 * 10**16,
            signedBlockWindow: 100,
            minSignedPerWindow: 5 * 10**16,
            inflationRateChange: 13 * 10**16,
            goalBonded: 67 * 10**16, 
            blocksPerYear: 6311520,  
            inflationMax: 20 * 10**16,
            inflationMin: 7 * 10**16    
        });
    }

    // @notice Will receive any eth sent to the contract
    function deposit() external payable {}

    function setParams(
        uint256 maxValidators,
        uint256 downtimeJailDuration,
        uint256 baseProposerReward,
        uint256 bonusProposerReward,
        uint256 slashFractionDowntime,
        uint256 unbondingTime,
        uint256 slashFractionDoubleSign,
        uint256 signedBlockWindow,
        uint256 minSignedPerWindow
    ) public onlyOwner {
        if (maxValidators > 0) {
            _params.maxValidators = maxValidators;
        }
        if (downtimeJailDuration > 0) {
            _params.downtimeJailDuration = downtimeJailDuration;
        }
        if (baseProposerReward > 0) {
            _params.baseProposerReward = baseProposerReward;
        }
        if (bonusProposerReward > 0) {
            _params.bonusProposerReward = bonusProposerReward;
        }
        if (slashFractionDowntime > 0) {
            _params.slashFractionDowntime = slashFractionDowntime;
        }
        if (unbondingTime > 0) {
            _params.unbondingTime = unbondingTime;
        }
        if (slashFractionDoubleSign > 0) {
            _params.slashFractionDoubleSign = slashFractionDoubleSign;
        }
 
        if (signedBlockWindow > 0) {
            _params.signedBlockWindow = signedBlockWindow;
        }

        if (minSignedPerWindow > 0) {
            _params.minSignedPerWindow = minSignedPerWindow;
        }
    }

    function setTotalBonded(uint256 amount) public onlyOwner {
        totalBonded = amount;
    }

    function setMintParams(
        uint256 inflationRateChange,
        uint256 goalBonded,
        uint256 blocksPerYear,
        uint256 inflationMax,
        uint256 inflationMin
    ) public onlyOwner {
        if (inflationRateChange > 0) {
            _params.inflationRateChange = inflationRateChange;
        }
        if (goalBonded > 0) {
            _params.goalBonded = goalBonded;
        }
        if (blocksPerYear > 0) {
            _params.blocksPerYear = blocksPerYear;
        }
        if (inflationMax > 0) {
            _params.inflationMax = inflationMax;
        }
        if (inflationMin > 0) {
            _params.inflationMin = inflationMin;
        }
    }

    // create new validator
    function createValidator(
        uint256 commssionRate,
        uint256 maxRate,
        uint256 maxChangeRate,
        uint256 minSeftDelegation
    ) public payable {
        _createValidator(
            msg.sender,
            msg.value,
            commssionRate,
            maxRate,
            maxChangeRate,
            minSeftDelegation
        );

        emit CreateValidator(
            msg.sender,
            msg.value,
            commssionRate,
            maxRate,
            maxChangeRate,
            minSeftDelegation
        );
    }

    function _createValidator(
        address payable valAddr,
        uint256 amount,
        uint256 rate,
        uint256 maxRate,
        uint256 maxChangeRate,
        uint256 minSelfDelegation
    ) private {
        require(!vals.contains(valAddr), "validator already exist");
        require(amount > 0, "invalid delegation amount");
        require(amount > minSelfDelegation, "self delegation below minimum");
        require(
            maxRate <= oneDec,
            "commission max rate cannot be more than 100%"
        );
        require(
            maxChangeRate <= maxRate,
            "commission max change rate can not be more than the max rate"
        );
        require(
            rate <= maxRate,
            "commission rate cannot be more than the max rate"
        );

        Commission memory commission = Commission({
            rate: rate,
            maxRate: maxRate,
            maxChangeRate: maxChangeRate
        });

        vals.add(valAddr);
        // solhint-disable-next-line not-rely-on-time
        uint256 updateTime = block.timestamp;
        valByAddr[valAddr].commission = commission;
        valByAddr[valAddr].minSelfDelegation = minSelfDelegation;
        valByAddr[valAddr].updateTime = updateTime;
        valByAddr[valAddr].owner = valAddr;
        _afterValidatorCreated(valAddr);
        _delegate(valAddr, valAddr, amount);
        valSigningInfos[valAddr].startHeight = block.number;
    }

    // update validator
    function updateValidator(uint256 commissionRate, uint256 minSelfDelegation)
        public
    {
        _updateValidator(msg.sender, commissionRate, minSelfDelegation);
    }

    function _updateValidator(
        address valAddr,
        uint256 commissionRate,
        uint256 minSelfDelegation
    ) private {
        require(vals.contains(valAddr), "validator not found");
        Validator storage val = valByAddr[valAddr];
        if (commissionRate > 0) {
            require(
                // solhint-disable-next-line not-rely-on-time
                block.timestamp.sub(val.updateTime) >= 86400,
                "commission cannot be changed more than one in 24h"
            );
            require(
                commissionRate <= val.commission.maxRate,
                "commission cannot be more than the max rate"
            );
            require(
                commissionRate.sub(val.commission.rate) <=
                    val.commission.maxChangeRate,
                "commission cannot be changed more than max change rate"
            );
        }
        if (minSelfDelegation > 0) {
            require(
                minSelfDelegation > val.minSelfDelegation,
                "minimum self delegation cannot be decrease"
            );
            require(
                minSelfDelegation <= val.tokens,
                "self delegation below minimum"
            );
            val.minSelfDelegation = minSelfDelegation;
        }

        if (commissionRate > 0) {
            val.commission.rate = commissionRate;
            // solhint-disable-next-line not-rely-on-time
            val.updateTime = block.timestamp;
        }

        emit UpdateValidator(msg.sender, commissionRate, minSelfDelegation);
    }

    function _afterValidatorCreated(address valAddr) private {
        _initializeValidator(valAddr);
    }

    function _afterDelegationModified(address valAddr, address delAddr)
        private
    {
        _initializeDelegation(valAddr, delAddr);
    }

    function _delegate(address payable delAddr, address valAddr, uint256 amount)
        private
    {
        // add delegation if not exists;
        if (!dels[valAddr].contains(delAddr)) {
            dels[valAddr].add(delAddr);
            delVals[delAddr].add(valAddr);
            delByAddr[valAddr][delAddr].owner = delAddr;
            _beforeDelegationCreated(valAddr);
        } else {
            _beforeDelegationSharesModified(valAddr, delAddr);
        }

        uint256 shared = _addTokenFromDel(valAddr, amount);

        totalBonded = totalBonded.add(amount);

        // increment stake amount
        Delegation storage del = delByAddr[valAddr][delAddr];
        del.shares = del.shares.add(shared);
        _afterDelegationModified(valAddr, delAddr);
        addValidatorRank(valAddr);
        emit Delegate(valAddr, delAddr, amount);
    }

    // calculate share delegator's
    function _addTokenFromDel(address valAddr, uint256 amount)
        private
        returns (uint256)
    {
        Validator storage val = valByAddr[valAddr];
        uint256 issuedShares = 0;
        if (val.tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(valAddr, amount);
        }
        val.tokens = val.tokens.add(amount);
        val.delegationShares = val.delegationShares.add(issuedShares);
        return issuedShares;
    }

    function delegate(address valAddr) public payable {
        require(vals.contains(valAddr), "validator not found");
        require(msg.value > 0, "invalid delegation amount");
        _delegate(msg.sender, valAddr, msg.value);
    }

    function _undelegate(
        address valAddr,
        address payable delAddr,
        uint256 amount
    ) private {
        require(
            ubdEntries[valAddr][delAddr].length < 7,
            "too many unbonding delegation entries"
        );
        require(dels[valAddr].contains(delAddr), "delegation not found");
        _beforeDelegationSharesModified(valAddr, delAddr);

        Validator storage val = valByAddr[valAddr];
        Delegation storage del = delByAddr[valAddr][delAddr];
        uint256 shares = _shareFromToken(valAddr, amount);
        require(del.shares >= shares, "not enough delegation shares");
        del.shares -= shares;
        _afterDelegationModified(valAddr, delAddr);
        bool isValidatorOperator = valAddr == delAddr;
        if (
            isValidatorOperator &&
            !val.jailed &&
            _tokenFromShare(valAddr, del.shares) < val.minSelfDelegation
        ) {
            _jail(valAddr);
        }

        uint256 amountRemoved = _removeDelShares(valAddr, shares);
        val.ubdEntryCount++;
        if (val.tokens.div(powerReduction) == 0) {
            removeValidatorRank(valAddr);
        } else {
            addValidatorRank(valAddr);
        }

        // solhint-disable-next-line not-rely-on-time
        uint256 completionTime = block.timestamp.add(_params.unbondingTime);
        ubdEntries[valAddr][delAddr].push(
            UBDEntry({
                completionTime: completionTime,
                blockHeight: block.number,
                amount: amountRemoved
            })
        );

        emit Undelegate(valAddr, msg.sender, amount, completionTime);
    }
    
    // remove share delegator's
    function _removeDelShares(address valAddr, uint256 shares)
        private
        returns (uint256)
    {
        Validator storage val = valByAddr[valAddr];
        uint256 remainingShares = val.delegationShares;
        uint256 issuedTokens = 0;
        remainingShares = remainingShares.sub(shares);
        if (remainingShares == 0) {
            issuedTokens = val.tokens;
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
        valByAddr[valAddr].jailed = true;
        removeValidatorRank(valAddr);
    }

    // slash Validator
    function _slash(
        address valAddr,
        uint256 infrationHeight,
        uint256 power,
        uint256 slashFactor
    ) private {
        require(
            infrationHeight <= block.number,
            "cannot slash infrations in the future"
        );
        Validator storage val = valByAddr[valAddr];
        uint256 slashAmount = power.mul(powerReduction).mulTrun(slashFactor);
        if (infrationHeight < block.number) {
            uint256 totalDel = dels[valAddr].length();
            for (uint256 i = 0; i < totalDel; i++) {
                address delAddr = dels[valAddr].at(i);
                UBDEntry[] storage entries = ubdEntries[valAddr][delAddr];
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
        if (tokensToBurn > val.tokens) {
            tokensToBurn = val.tokens;
        }

        if (val.tokens > 0) {
            uint256 effectiveFraction = tokensToBurn.divTrun(val.tokens);
            _beforeValidatorSlashed(valAddr, effectiveFraction);
        }

        val.tokens = val.tokens.sub(tokensToBurn);
        _burn(tokensToBurn);
        removeValidatorRank(valAddr);
    }

    function _burn(uint256 amount) private {
        totalBonded -= amount;
        totalSupply -= amount;
        emit Burn(amount);
    }

    function _updateValidatorSlashFraction(address valAddr, uint256 fraction)
        private
    {
        uint256 newPeriod = _incrementValidatorPeriod(valAddr);
        _incrementReferenceCount(valAddr, newPeriod);
        valByAddr[valAddr].slashEvents[valByAddr[valAddr]
            .slashEventCounter] = ValSlashEvent({
            validatorPeriod: newPeriod,
            fraction: fraction,
            height: block.number
        });
        valByAddr[valAddr].slashEventCounter++;
    }

    function _beforeValidatorSlashed(address valAddr, uint256 fraction)
        private
    {
        _updateValidatorSlashFraction(valAddr, fraction);
    }

    function _withdraw(address valAddr, address payable delAddr) private {
        require(dels[valAddr].contains(delAddr), "delegation not found");
        Delegation memory del = delByAddr[valAddr][delAddr];
        Validator storage val = valByAddr[valAddr];
        UBDEntry[] storage entries = ubdEntries[valAddr][delAddr];
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
        delAddr.transfer(amount);
        totalBonded = totalBonded.sub(amount);

        if (del.shares == 0 && entries.length == 0) {
            _removeDelegation(valAddr, delAddr);
        }

        val.ubdEntryCount = val.ubdEntryCount.sub(entryCount);
        if (val.delegationShares == 0 && val.ubdEntryCount == 0) {
            _removeValidator(valAddr);
        }

        emit Withdraw(valAddr, delAddr, amount);
    }
    
    // remove delegation
    function _removeDelegation(address valAddr, address delAddr) private {
        dels[valAddr].remove(delAddr);
        delete delByAddr[valAddr][delAddr];
        delete delStartingInfo[valAddr][delAddr];
        delVals[delAddr].remove(valAddr);
    }
    
    // remove validator
    function _removeValidator(address valAddr) private {
        // remove validator
        vals.remove(valAddr);
        uint256 commission = valAccumulatedCommission[valAddr];
        if (commission > 0) {
            // substract total supply
            totalSupply = totalSupply.sub(commission);
        }

        // remove other index
        delete valAccumulatedCommission[valAddr];
        delete valCurrentRewards[valAddr];
        delete valSigningInfos[valAddr];

        delete valByAddr[valAddr];
        removeValidatorRank(valAddr);
    }
    
    // withdraw token delegator's
    function withdraw(address valAddr) public {
        _withdraw(valAddr, msg.sender);
    }

    // calculate the total rewards accrued by a delegation
    function _calculateDelegationRewards(
        address valAddr,
        address delAddr,
        uint256 endingPeriod
    ) private view returns (uint256) {
        // fetch starting info for delegation
        DelStartingInfo memory startingInfo = delStartingInfo[valAddr][delAddr];
        uint256 rewards = 0;
        uint256 slashEventCounter = valByAddr[valAddr].slashEventCounter;
        for (uint256 i = 0; i < slashEventCounter; i++) {
            ValSlashEvent memory slashEvent = valByAddr[valAddr].slashEvents[i];
            if (
                slashEvent.height > startingInfo.height &&
                slashEvent.height < block.number
            ) {
                uint256 _endingPeriod = slashEvent.validatorPeriod;
                if (_endingPeriod > startingInfo.previousPeriod) {
                    rewards += _calculateDelegationRewardsBetween(
                        valAddr,
                        startingInfo.previousPeriod,
                        slashEvent.validatorPeriod,
                        startingInfo.stake
                    );
                    startingInfo.stake = startingInfo.stake.mulTrun(
                        oneDec.sub(slashEvent.fraction)
                    );
                    startingInfo.previousPeriod = _endingPeriod;
                }
            }
        }
        rewards += _calculateDelegationRewardsBetween(
            valAddr,
            startingInfo.previousPeriod,
            endingPeriod,
            startingInfo.stake
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
        ValHRewards memory starting = valByAddr[valAddr]
            .hRewards[startingPeriod];
        ValHRewards memory ending = valByAddr[valAddr].hRewards[endingPeriod];
        uint256 difference = ending.cumulativeRewardRatio.sub(
            starting.cumulativeRewardRatio
        );
        return stake.mulTrun(difference); // return staking * (ending - starting)
    }

    // increment validator period, returning the period just ended
    function _incrementValidatorPeriod(address valAddr)
        private
        returns (uint256)
    {
        Validator memory val = valByAddr[valAddr];

        ValCurrentReward storage rewards = valCurrentRewards[valAddr];
        uint256 previousPeriod = rewards.period.sub(1);
        uint256 current = 0;
        if (rewards.reward > 0) {
            current = rewards.reward.divTrun(val.tokens);
        }
        uint256 historical = valByAddr[valAddr].hRewards[previousPeriod]
            .cumulativeRewardRatio;
        _decrementReferenceCount(valAddr, previousPeriod);

        valByAddr[valAddr].hRewards[rewards.period]
            .cumulativeRewardRatio = historical.add(current);
        valByAddr[valAddr].hRewards[rewards.period].reference_count = 1;
        rewards.period++;
        rewards.reward = 0;
        return previousPeriod.add(1);
    }

    // decrement the reference count for a historical rewards value, and delete if zero references remain
    function _decrementReferenceCount(address valAddr, uint256 period) private {
        valByAddr[valAddr].hRewards[period].reference_count--;
        if (valByAddr[valAddr].hRewards[period].reference_count == 0) {
            delete valByAddr[valAddr].hRewards[period];
        }
    }

    // increment the reference count for a historical rewards value
    function _incrementReferenceCount(address valAddr, uint256 period) private {
        valByAddr[valAddr].hRewards[period].reference_count++;
    }

    // initialize starting info for a new delegation
    function _initializeDelegation(address valAddr, address delAddr) private {
        Delegation storage del = delByAddr[valAddr][delAddr];
        uint256 previousPeriod = valCurrentRewards[valAddr].period - 1;
        _incrementReferenceCount(valAddr, previousPeriod);
        delStartingInfo[valAddr][delAddr].height = block.number;
        delStartingInfo[valAddr][delAddr].previousPeriod = previousPeriod;
        uint256 stake = _tokenFromShare(valAddr, del.shares);
        delStartingInfo[valAddr][delAddr].stake = stake;
    }

   // initialize starting info for a new validator
    function _initializeValidator(address valAddr) private {
        valCurrentRewards[valAddr].period = 1;
        valCurrentRewards[valAddr].reward = 0;
        valAccumulatedCommission[valAddr] = 0;
    }

    function _beforeDelegationCreated(address valAddr) private {
        _incrementValidatorPeriod(valAddr);
    }

    function _beforeDelegationSharesModified(
        address valAddr,
        address payable delAddr
    ) private {
        _withdrawRewards(valAddr, delAddr);
    }

    function _withdrawRewards(address valAddr, address payable delAddr)
        private
    {
        uint256 endingPeriod = _incrementValidatorPeriod(valAddr);
        uint256 rewards = _calculateDelegationRewards(
            valAddr,
            delAddr,
            endingPeriod
        );
        _decrementReferenceCount(
            valAddr,
            delStartingInfo[valAddr][delAddr].previousPeriod
        );
        delete delStartingInfo[valAddr][delAddr];
        if (rewards > 0) {
            delAddr.transfer(rewards);
            emit WithdrawDelegationRewards(valAddr, delAddr, rewards);
        }
    }

    // withdraw rewards from a delegation
    function withdrawReward(address valAddr) public {
        require(dels[valAddr].contains(msg.sender), "delegator not found");
        _withdrawRewards(valAddr, msg.sender);
        _initializeDelegation(valAddr, msg.sender);
    }

    // get rewards from a delegation
    function getDelegationRewards(address valAddr, address delAddr)
        public
        view
        returns (uint256)
    {
        require(dels[valAddr].contains(delAddr), "delegation not found");
        Validator memory val = valByAddr[valAddr];
        Delegation memory del = delByAddr[valAddr][delAddr];
        uint256 rewards = _calculateDelegationRewards(
            valAddr,
            delAddr,
            valCurrentRewards[valAddr].period - 1
        );

        uint256 currentReward = valCurrentRewards[valAddr].reward;
        if (currentReward > 0) {
            uint256 stake = _tokenFromShare(valAddr, del.shares);
            rewards += stake.mulTrun(currentReward.divTrun(val.tokens));
        }
        return rewards;
    }

    function _withdrawValidatorCommission(address payable valAddr) private {
        require(vals.contains(valAddr), "validator not found");
        uint256 commission = valAccumulatedCommission[valAddr];
        require(commission > 0, "no validator commission to reward");
        valAddr.transfer(commission);
        valAccumulatedCommission[valAddr] = 0;
        emit WithdrawCommissionReward(valAddr, commission);
    }

    // withdraw validator commission
    function withdrawValidatorCommission() public {
        _withdrawValidatorCommission(msg.sender);
    }

    // get infor of validator
    function getValidator(address valAddr)
        public
        view
        returns (uint256, uint256, bool, uint256, uint256, uint256, uint256)
    {
        require(vals.contains(valAddr), "validator not found");
        Validator memory val = valByAddr[valAddr];
        uint256 rate = val.commission.rate;
        uint256 maxRate = val.commission.maxRate;
        uint256 maxChangeRate = val.commission.maxChangeRate;
        uint256 slashEventCounter = val.slashEventCounter;
        return (val.tokens, val.delegationShares, val.jailed, rate, maxRate, maxChangeRate, slashEventCounter);
    }

    // get all delegation by validator
    function getDelegationsByValidator(address valAddr)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        require(vals.contains(valAddr), "validator not found");
        uint256 total = dels[valAddr].length();
        address[] memory delAddrs = new address[](total);
        uint256[] memory shares = new uint256[](total);
        for (uint256 i = 0; i < total; i++) {
            address delAddr = dels[valAddr].at(i);
            delAddrs[i] = delAddr;
            shares[i] = delByAddr[valAddr][delAddr].shares;
        }
        return (delAddrs, shares);
    }

    // get all validator of delegator delegated
    function getValidatorsByDelegator(address delAddr)
        public
        view
        returns (address[] memory)
    {
        uint256 total = delVals[delAddr].length();
        address[] memory addrs = new address[](total);
        for (uint256 i = 0; i < total; i++) {
            addrs[i] = delVals[delAddr].at(i);
        }

        return addrs;
    }
    
    // get all reward of a delegator
    function getAllDelegatorRewards(address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 total = delVals[delAddr].length();
        uint256 rewards = 0;
        for (uint256 i = 0; i < total; i++) {
            address valAddr = delVals[delAddr].at(i);
            rewards += getDelegationRewards(valAddr, delAddr);
        }
        return rewards;
    }

    function getDelegatorStake(address valAddr, address delAddr)
        public
        view
        returns (uint256)
    {
        require(dels[valAddr].contains(delAddr), "delegation not found");
        Delegation memory del = delByAddr[valAddr][delAddr];
        return _tokenFromShare(valAddr, del.shares);
    }

    function getAllDelegatorStake(address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 stake = 0;
        uint256 total = delVals[delAddr].length();
        for (uint256 i = 0; i < total; i++) {
            address valAddr = delVals[delAddr].at(i);
            stake += getDelegatorStake(valAddr, delAddr);
        }
        return stake;
    }
    
    // token worth of provided delegator shares
    function _tokenFromShare(address valAddr, uint256 shares)
        private
        view
        returns (uint256)
    {
        Validator memory val = valByAddr[valAddr];
        return shares.mul(val.tokens).div(val.delegationShares);
    }
    
    // shares worth of delegator's bond
    function _shareFromToken(address valAddr, uint256 amount)
        private
        view
        returns (uint256)
    {
        Validator memory val = valByAddr[valAddr];
        return val.delegationShares.mul(amount).div(val.tokens);
    }

    function getUBDEntries(address valAddr, address delAddr)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256 total = ubdEntries[valAddr][delAddr].length;
        uint256[] memory balances = new uint256[](total);
        uint256[] memory completionTime = new uint256[](total);

        for (uint256 i = 0; i < total; i++) {
            completionTime[i] = ubdEntries[valAddr][delAddr][i].completionTime;
            balances[i] = ubdEntries[valAddr][delAddr][i].amount;
        }
        return (balances, completionTime);
    }

    // get slash event for Validator
    function getValidatorSlashEvents(address valAddr)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256 total = valByAddr[valAddr].slashEventCounter;
        uint256[] memory fraction = new uint256[](total);
        uint256[] memory height = new uint256[](total);
        for (uint256 i = 0; i < total; i++) {
            fraction[i] = valByAddr[valAddr].slashEvents[i].fraction;
            height[i] = valByAddr[valAddr].slashEvents[i].height;
        }
        return (height, fraction);
    }

    function _doubleSign(
        address valAddr,
        uint256 votingPower,
        uint256 distributionHeight
    ) private {
        if (!vals.contains(valAddr)) return;

        // reason: doubleSign
        emit Slashed(valAddr, votingPower, 2);

        _slash(
            valAddr,
            distributionHeight.sub(1),
            votingPower,
            _params.slashFractionDoubleSign
        );
        _jail(valAddr);
        // // (Dec 31, 9999 - 23:59:59 GMT).
        valSigningInfos[valAddr].jailedUntil = 253402300799;
        valSigningInfos[valAddr].tombstoned = true;
    }

    // check double sign, must be called once per validator per block
    function doubleSign(
        address valAddr,
        uint256 votingPower,
        uint256 distributionHeight
    ) public {
        _doubleSign(valAddr, votingPower, distributionHeight);
    }

    // validate validator signature, must be called once per validator per block
    function _validateSignature(
        address valAddr,
        uint256 votingPower,
        bool signed
    ) private {
        Validator storage val = valByAddr[valAddr];
        ValSigningInfo storage signInfo = valSigningInfos[valAddr];
        // counts blocks the validator should have signed
        uint256 index = signInfo.indexOffset % _params.signedBlockWindow;
        signInfo.indexOffset++;
        bool previous = valByAddr[valAddr].missedBlock.items[index];
        bool missed = !signed;
        if (!previous && missed) { // value has changed from not missed to missed, increment counter
            signInfo.missedBlockCounter++;
            valByAddr[valAddr].missedBlock.items[index] = true;
        } else if (previous && !missed) { // value has changed from missed to not missed, decrement counter
            signInfo.missedBlockCounter--;
            valByAddr[valAddr].missedBlock.items[index] = false;
        }

        if (missed) {
            emit Liveness(valAddr, signInfo.missedBlockCounter, block.number);
        }

        uint256 minHeight = signInfo.startHeight + _params.signedBlockWindow;

        uint256 minSignedPerWindow = _params.signedBlockWindow.mulTrun(
            _params.minSignedPerWindow
        );
        uint256 maxMissed = _params.signedBlockWindow - minSignedPerWindow;
        // if past the minimum height and the validator has missed too many blocks, punish them
        if (
            block.number > minHeight && signInfo.missedBlockCounter > maxMissed
        ) {
            if (!val.jailed) {
                // reason: missing signature
                emit Slashed(valAddr, votingPower, 1);

                _slash(
                    valAddr,
                    block.number - 2,
                    votingPower,
                    _params.slashFractionDowntime
                );
                _jail(valAddr);

                // solhint-disable-next-line not-rely-on-time
                signInfo.jailedUntil = block.timestamp.add(
                    _params.downtimeJailDuration
                );
                // reset the counter & array so that the validator won't be immediately slashed for downtime upon rebonding
                signInfo.missedBlockCounter = 0;
                signInfo.indexOffset = 0;
                delete valByAddr[valAddr].missedBlock;
            }
        }
    }

    // _allocateTokens handles distribution of the collected fees
    function _allocateTokens(
        uint256 sumPreviousPrecommitPower,
        uint256 totalPreviousVotingPower,
        address previousProposer,
        address[] memory addrs,
        uint256[] memory powers
    ) private {
        // calculate fraction votes
        uint256 previousFractionVotes = sumPreviousPrecommitPower.divTrun(
            totalPreviousVotingPower
        );
        // calculate previous proposer reward
        uint256 proposerMultiplier = _params.baseProposerReward.add(
            _params.bonusProposerReward.mulTrun(previousFractionVotes)
        );
        uint256 proposerReward = _feesCollected.mulTrun(proposerMultiplier);
        _allocateTokensToValidator(previousProposer, proposerReward);

        uint256 voteMultiplier = oneDec;
        voteMultiplier = voteMultiplier.sub(proposerMultiplier);
        for (uint256 i = 0; i < addrs.length; i++) {
            uint256 powerFraction = powers[i].divTrun(totalPreviousVotingPower);
            uint256 rewards = _feesCollected.mulTrun(voteMultiplier).mulTrun(
                powerFraction
            );
            // allocate token to a validator
            _allocateTokensToValidator(addrs[i], rewards);
        }
    }

    // _allocateTokensToValidator allocate tokens to a particular validator, splitting according to commission
    function _allocateTokensToValidator(address valAddr, uint256 rewards)
        private
    {
        uint256 commission = rewards.mulTrun(
            valByAddr[valAddr].commission.rate
        );
        uint256 shared = rewards.sub(commission);
        valAccumulatedCommission[valAddr] += commission;
        valCurrentRewards[valAddr].reward += shared;
    }

    function _finalizeCommit(
        address[] memory addrs,
        uint256[] memory powers,
        bool[] memory signed
    ) private {
        uint256 previousTotalPower = 0;
        uint256 sumPreviousPrecommitPower = 0;
        for (uint256 i = 0; i < powers.length; i++) {
            previousTotalPower += powers[i];
            if (signed[i]) {
                sumPreviousPrecommitPower += powers[i];
            }
        }
        if (block.number > 1) {
            _allocateTokens(
                sumPreviousPrecommitPower,
                previousTotalPower,
                _previousProposer,
                addrs,
                powers
            );
        }
        _previousProposer = block.coinbase;

        for (uint256 i = 0; i < powers.length; i++) {
            _validateSignature(addrs[i], powers[i], signed[i]);
        }
    }

    // finalize commit, must be called once per validator per block
    function finalizeCommit(
        address[] memory addrs,
        uint256[] memory powers,
        bool[] memory signed
    ) public onlyOwner {
        _finalizeCommit(addrs, powers, signed);
    }

    function setPreviousProposer(address previousProposer) public onlyOwner {
        _previousProposer = previousProposer;
    }

    function getValidators()
        public
        view
        returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        uint256 total = vals.length();
        address[] memory valAddrs = new address[](total);
        uint256[] memory tokens = new uint256[](total);
        uint256[] memory delegationsShares = new uint256[](total);
        for (uint256 i = 0; i < total; i++) {
            address valAddr = vals.at(i);
            valAddrs[i] = valAddr;
            tokens[i] = valByAddr[valAddr].tokens;
            delegationsShares[i] = valByAddr[valAddr].delegationShares;
        }
        return (valAddrs, tokens, delegationsShares);
    }

    // getMissedBlock returns array of missed blocks for given validator address
    function getMissedBlock(address valAddr)
        public
        view
        returns (bool[] memory)
    {
        bool[] memory missedBlock = new bool[](_params.signedBlockWindow);
        for (uint256 i = 0; i < _params.signedBlockWindow; i++) {
            missedBlock[i] = valByAddr[valAddr].missedBlock.items[i];
        }

        return missedBlock;
    }

    // Mint
    //  --------------------------------------------------

    // @dev mints new tokens for the previous block. Returns fee collected
    function mint() public onlyOwner returns (uint256) {
        // recalculate inflation rate
        inflation = nextInflationRate();
        // recalculate annual provisions
        annualProvision = nextAnnualProvisions();
        // update fee collected
        _feesCollected = getBlockProvision();
        totalSupply += _feesCollected;
        emit Minted(_feesCollected);
        return _feesCollected;
    }

    function setInflation(uint256 _inflation) public onlyOwner {
        inflation = _inflation;
    }

    // recalculate inflation rate 
    function nextInflationRate() public view returns (uint256) {
        uint256 bondedRatio = totalBonded.divTrun(totalSupply);
        uint256 inflationRateChangePerYear;
        uint256 inflationRateChange;
        uint256 inflationRate;
        if (bondedRatio < _params.goalBonded) {
            inflationRateChangePerYear = oneDec
                .sub(bondedRatio.divTrun(_params.goalBonded))
                .mulTrun(_params.inflationRateChange);
            inflationRateChange = inflationRateChangePerYear.div(
                _params.blocksPerYear
            );
            inflationRate = inflation.add(inflationRateChange);
        } else {
            inflationRateChangePerYear = bondedRatio
                .divTrun(_params.goalBonded)
                .sub(oneDec)
                .mulTrun(_params.inflationRateChange);
            inflationRateChange = inflationRateChangePerYear.div(
                _params.blocksPerYear
            );
            if (inflation > inflationRateChange) {
                inflationRate = inflation.sub(inflationRateChange);
            } else {
                inflationRate = 0;
            }
        }
        if (inflationRate > _params.inflationMax) {
            inflationRate = _params.inflationMax;
        }
        if (inflationRate < _params.inflationMin) {
            inflationRate = _params.inflationMin;
        }
        return inflationRate;
    }

    // recalculate annual provision
    function nextAnnualProvisions() public view returns (uint256) {
        return inflation.mulTrun(totalSupply);
    }

    function setAnnualProvision(uint256 _annualProvision) public onlyOwner {
        annualProvision = _annualProvision;
    }

    function getBlockProvision() public view returns (uint256) {
        return annualProvision.div(_params.blocksPerYear);
    }

    function setTotalSupply(uint256 amount) public onlyOwner {
        totalSupply = amount;
    }

    // validator rank
    function addValidatorRank(address valAddr) private {
        uint256 idx = valRankIndexes[valAddr];
        uint256 valPower = getValidatorPower(valAddr);
        if (valPower == 0) return;
        if (idx == 0) {
            valRanks.push(valAddr);
            valRankIndexes[valAddr] = valRanks.length;
        }
        _needSort = true;
    }

    function removeValidatorRank(address valAddr) private {
        uint256 todDeleteIndex = valRankIndexes[valAddr];
        if (todDeleteIndex == 0) return;
        uint256 lastIndex = valRanks.length;
        address last = valRanks[lastIndex - 1];
        valRanks[todDeleteIndex - 1] = last;
        valRankIndexes[last] = todDeleteIndex;
        valRanks.pop();
        delete valRankIndexes[valAddr];
        _needSort = true;
    }

    function getValPowerByRank(uint256 rank) private view returns (uint256) {
        return getValidatorPower(valRanks[rank]);
    }

    function _sortValRank(int256 left, int256 right) internal {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = getValPowerByRank(uint256(left + (right - left) / 2));
        while (i <= j) {
            while (getValPowerByRank(uint256(i)) > pivot) i++;
            while (pivot > getValPowerByRank(uint256(j))) j--;
            if (i <= j) {
                address tmp = valRanks[uint256(i)];
                valRanks[uint256(i)] = valRanks[uint256(j)];
                valRanks[uint256(j)] = tmp;

                valRankIndexes[tmp] = uint256(j + 1);
                valRankIndexes[valRanks[uint256(i)]] = uint256(i + 1);

                i++;
                j--;
            }
        }
        if (left < j) _sortValRank(left, j);
        if (i < right) _sortValRank(i, right);
    }

    function _clearValRank() private {
        for (uint256 i = valRanks.length; i > 300; i --) {
            delete valRankIndexes[valRanks[i - 1]];
            valRanks.pop();
        }
    }

    function applyAndReturnValidatorSets()
        public
        onlyOwner
        returns (address[] memory, uint256[] memory)
    {
        if (_needSort && valRanks.length > 0) {
            _sortValRank(0, int256(valRanks.length - 1));
            _clearValRank();
            _needSort = false;
        }
        return getValidatorSets();
    }

    function getValidatorSets()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 maxVal = _params.maxValidators;
        if (maxVal > valRanks.length) {
            maxVal = valRanks.length;
        }
        address[] memory valAddrs = new address[](maxVal);
        uint256[] memory powers = new uint256[](maxVal);

        for (uint256 i = 0; i < maxVal; i++) {
            valAddrs[i] = valRanks[i];
            powers[i] = getValidatorPower(valRanks[i]);
        }
        return (valAddrs, powers);
    }

    // get voting power of the validator
    function getValidatorPower(address valAddr) public view returns (uint256) {
        return valByAddr[valAddr].tokens.div(powerReduction);
    }

    // slashing
    function _unjail(address valAddr) private {
        require(vals.contains(valAddr), "validator not found");
        Validator storage val = valByAddr[valAddr];
        require(val.jailed, "validator not jailed");
        // cannot be unjailed if tombstoned
        require(
            valSigningInfos[valAddr].tombstoned == false,
            "validator jailed"
        );
        uint256 jailedUntil = valSigningInfos[valAddr].jailedUntil;
        // solhint-disable-next-line not-rely-on-time
        require(jailedUntil < block.timestamp, "validator jailed");
        Delegation storage del = delByAddr[valAddr][valAddr];
        uint256 tokens = _tokenFromShare(valAddr, del.shares);
        require(
            tokens > val.minSelfDelegation,
            "self delegation too low to unjail"
        );

        valSigningInfos[valAddr].jailedUntil = 0;
        val.jailed = false;
        addValidatorRank(valAddr);
    }
    
// Unjail is used for unjailing a jailed validator, thus returning
// them into the bonded validator set, so they can begin receiving provisions
// and rewards again.
    function unjail() public {
        _unjail(msg.sender);
        emit UnJail(msg.sender);
    }
}