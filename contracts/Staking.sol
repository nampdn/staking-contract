pragma solidity  ^0.6.0;
import {SafeMath} from "./Safemath.sol";
import {IStaking} from "./IStaking.sol";

contract Staking is IStaking {
    using SafeMath for uint256;

    uint256 oneDec = 1 * 10**18;
    uint256 powerReduction = 1 * 10**6;

    struct Delegation {
        uint256 shares;
        address owner;
    }

    struct UBDEntry {
        uint256 amount;
        uint256 blockHeight;
        uint256 completionTime;
    }

    struct Commission {
        uint256 rate;
        uint256 maxRate;
        uint256 maxChangeRate;
    }

    struct Validator {
        address owner;
        uint256 tokens;
        uint256 delegationShares;
        bool jailed;
        Commission commission;
        uint256 minSelfDelegation;
        uint256 updateTime;
        uint256 ubdEntryCount;
    }

    struct DelStartingInfo {
        uint256 stake;
        uint256 previousPeriod;
        uint256 height;
    }

    struct ValSlashEvent {
        uint256 validatorPeriod;
        uint256 fraction;
        uint256 height;
    }

    struct ValCurrentReward {
        uint256 period;
        uint256 reward;
    }

    // validator historical rewards
    struct ValHRewards {
        uint256 cumulativeRewardRatio;
        uint256 reference_count;
    }

    struct ValSigningInfo {
        uint256 startHeight;
        uint256 indexOffset;
        bool tombstoned;
        uint256 missedBlockCounter;
        uint256 jailedUntil;
    }

    struct Params {
        uint256 baseProposerReward;
        uint256 bonusProposerReward;
        uint256 maxValidators;
        uint256 downtimeJailDuration;
        uint256 slashFractionDowntime;
        uint256 unbondingTime;
        uint256 slashFractionDoubleSign;
        uint256 signedBlockWindow;
        uint256 minSignedPerWindow;
        // mint params
        uint256 inflationRateChange;
        uint256 goalBonded;
        uint256 blocksPerYear;
        uint256 inflationMax;
        uint256 inflationMin;
    }

    Validator[] vals;
    mapping(address => mapping(address => uint256)) delsIdx;
    mapping(address => mapping(address => UBDEntry[])) ubdEntries;
    mapping(address => mapping(address => DelStartingInfo)) delStartingInfo;
    mapping(address => ValSlashEvent[]) valSlashEvents;
    mapping(address => ValCurrentReward) valCurrentRewards;
    mapping(address => ValHRewards[]) valHRewards;
    mapping(address => bool[]) missedBlock;
    mapping(address => ValSigningInfo) valSigningInfos;
    mapping(address => uint256) valAccumulatedCommission;
    mapping(address => Delegation[]) delegations;
    mapping(address => uint256) valsIdx;
    mapping(address => address[]) delVals;
    mapping(address => mapping(address => uint256)) delValsIndex;

    // sort
    address[] valsRank;
    mapping(address => uint256) validatorRankIndex;

    bool _needSort;

    // supply
    uint256 public totalSupply = 5000000000 * 10**18;
    uint256 public totalBonded;
    uint256 public inflation;
    uint256 public annualProvision;
    uint256 _feesCollected;

    address _root;

    // mint

    Params _params;
    address _previousProposer;

    modifier onlyRoot() {
        require(msg.sender == _root, "permission denied");
        _;
    }

    function setRoot(address newRoot) public {
        if (_root != address(0x0)) {
            require(msg.sender == _root, "permission denied");
        }
        _root = newRoot;
    }

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
    function deposit() external payable {
    }

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
    ) public onlyRoot {
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

    function setTotalBonded(uint256 amount) public onlyRoot {
        totalBonded = amount;
    }

    function setMintParams(
        uint256 inflationRateChange,
        uint256 goalBonded,
        uint256 blocksPerYear,
        uint256 inflationMax,
        uint256 inflationMin
    ) public onlyRoot {
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
        require(valsIdx[valAddr] == 0, "validator already exist");
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

        vals.push(
            Validator({
                owner: valAddr,
                tokens: 0,
                delegationShares: 0,
                jailed: false,
                commission: commission,
                minSelfDelegation: minSelfDelegation,
                // solhint-disable-next-line not-rely-on-time
                updateTime: block.timestamp,
                ubdEntryCount: 0
            })
        );
        valsIdx[valAddr] = vals.length;
        _afterValidatorCreated(valAddr);
        _delegate(valAddr, valAddr, amount);

        valSigningInfos[valAddr].startHeight = block.number;
    }

    function updateValidator(uint256 commissionRate, uint256 minSelfDelegation)
        public
    {
        require(valsIdx[msg.sender] > 0, "validator not found");
        Validator storage val = vals[valsIdx[msg.sender] - 1];
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

        emit UpdateValidator(
            msg.sender,
            commissionRate,
            minSelfDelegation
        );
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
        uint256 delIndex = delsIdx[valAddr][delAddr];
        // add delegation if not exists;
        if (delIndex == 0) {
            delegations[valAddr].push(Delegation({owner: delAddr, shares: 0}));
            delIndex = delegations[valAddr].length;
            delsIdx[valAddr][delAddr] = delIndex;

            // delegator validators index
            delVals[delAddr].push(valAddr);
            delValsIndex[delAddr][valAddr] = delVals[delAddr].length;

            _beforeDelegationCreated(valAddr);
        } else {
            _beforeDelegationSharesModified(valAddr, delAddr);
        }

        uint256 shared = _addTokenFromDel(valAddr, amount);

        totalBonded += amount;

        // increment stake amount
        Delegation storage del = delegations[valAddr][delIndex - 1];
        del.shares += shared;
        _afterDelegationModified(valAddr, delAddr);

        addValidatorRank(valAddr);
    }

    function _addTokenFromDel(address valAddr, uint256 amount)
        private
        returns (uint256)
    {
        Validator storage val = vals[valsIdx[valAddr] - 1];
        uint256 issuedShares = 0;
        if (val.tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(valAddr, amount);
        }
        val.tokens += amount;
        val.delegationShares += issuedShares;
        return issuedShares;
    }

    function delegate(address valAddr) public payable {
        require(valsIdx[valAddr] > 0, "validator not found");
        require(msg.value > 0, "invalid delegation amount");
        _delegate(msg.sender, valAddr, msg.value);
        emit Delegate(valAddr, msg.sender, msg.value);
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
        uint256 delegationIndex = delsIdx[valAddr][delAddr];
        require(delegationIndex > 0, "delegation not found");
        _beforeDelegationSharesModified(valAddr, delAddr);

        Validator storage val = vals[valsIdx[valAddr] - 1];
        Delegation storage del = delegations[valAddr][delegationIndex - 1];
        uint256 shares = _shareFromToken(valAddr, amount);
        require(del.shares >= shares, "invalid undelegate amount");
        del.shares -= shares;

        if (del.shares == 0) {
            _removeDelegation(valAddr, delAddr);
        } else {
            _afterDelegationModified(valAddr, delAddr);
        }

        bool isValidatorOperator = valAddr == delAddr;
        if (
            isValidatorOperator &&
            !val.jailed &&
            _tokenFromShare(valAddr, del.shares) < val.minSelfDelegation
        ) {
            _jail(valAddr);
        }

        uint256 amountRemoved = _removeDelShares(valAddr, shares);
        addValidatorRank(valAddr);
        val.ubdEntryCount++;

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

    function _removeDelShares(address valAddr, uint256 shares)
        private
        returns (uint256)
    {
        Validator storage val = vals[valsIdx[valAddr] - 1];
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
        vals[valsIdx[valAddr] - 1].jailed = true;
        removeValidatorRank(valAddr);
    }

    function _slash(
        address valAddr,
        uint256 infrationHeight,
        uint256 power,
        uint256 slashFactor
    ) private {
        require(infrationHeight <= block.number, "");
        Validator storage val = vals[valsIdx[valAddr] - 1];
        uint256 slashAmount = power.mul(powerReduction).mulTrun(slashFactor);
        if (infrationHeight < block.number) {
            for (uint256 i = 0; i < delegations[valAddr].length; i++) {
                address delAddr = delegations[valAddr][i].owner;
                UBDEntry[] storage entries = ubdEntries[valAddr][delAddr];
                for (uint256 j = 0; j < entries.length; j++) {
                    UBDEntry storage entry = entries[j];
                    if (entry.blockHeight > infrationHeight) {
                        uint256 amountSlashed = entry.amount.mulTrun(
                            slashFactor
                        );
                        entry.amount -= amountSlashed;
                        slashAmount -= amountSlashed;
                    }
                }
            }
        }
        _beforeValidatorSlashed(valAddr, slashFactor);
        val.tokens -= slashAmount;
        _burn(slashAmount);
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
        valSlashEvents[valAddr].push(
            ValSlashEvent({
                validatorPeriod: newPeriod,
                fraction: fraction,
                height: block.number
            })
        );
    }

    function _beforeValidatorSlashed(address valAddr, uint256 fraction) private {
        _updateValidatorSlashFraction(valAddr, fraction);
    }

    function getTotalSupply() public view returns (uint256) {
        return totalSupply;
    }

    function _withdraw(address valAddr, address payable delAddr) private {
        UBDEntry[] storage entries = ubdEntries[valAddr][delAddr];
        uint256 amount = 0;
        uint256 entryCount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            // solhint-disable-next-line not-rely-on-time
            if (entries[i].completionTime < block.timestamp) {
                amount += entries[i].amount;
                entries[i] = entries[entries.length - 1];
                entries.pop();
                i--;
                entryCount++;
            }
        }
        require(amount > 0, "no unbonding amount to withdraw");
        delAddr.transfer(amount);
        totalBonded -= amount;

        uint256 valIndex = valsIdx[valAddr];
        Validator storage val = vals[valIndex - 1];
        val.ubdEntryCount -= entryCount;
        if (val.delegationShares == 0 && val.ubdEntryCount == 0) {
            _removeValidator(valAddr);
        }

        emit Withdraw(valAddr, delAddr, amount);
    }

    function _removeDelegation(address valAddr, address delAddr) private {
        // delete delegation and delegation index
        uint256 index = delsIdx[valAddr][delAddr];
        uint256 lastIndex = delegations[valAddr].length;
        Delegation memory last = delegations[valAddr][lastIndex - 1];

        delegations[valAddr][index - 1] = last;
        delegations[valAddr].pop();
        delsIdx[valAddr][last.owner] = index;

        // delete other info
        delete delsIdx[valAddr][delAddr];
        delete delStartingInfo[valAddr][delAddr];

        _removeDelegatorValidatorIndex(valAddr, delAddr);
    }

    function _removeDelegatorValidatorIndex(address valAddr, address delAddr)
        private
    {
        uint256 index = delValsIndex[delAddr][valAddr];
        uint256 lastIndex = delVals[delAddr].length;
        address last = delVals[delAddr][lastIndex - 1];
        delVals[delAddr][index - 1] = last;
        delValsIndex[delAddr][last] = index;
        delVals[delAddr].pop();
        delete delValsIndex[delAddr][valAddr];
    }

    function _removeValidator(address valAddr) private {
        // remove validator
        uint256 valIdx = valsIdx[valAddr];
        uint256 lastIndex = vals.length;
        Validator memory last = vals[lastIndex - 1];
        vals[valIdx - 1] = last;
        vals.pop();
        valsIdx[last.owner] = valIdx;
        delete valsIdx[valAddr];

        // remove other index
        delete valSlashEvents[valAddr];
        delete valAccumulatedCommission[valAddr];
        delete valHRewards[valAddr];
        delete valCurrentRewards[valAddr];
        delete valHRewards[valAddr];
        delete missedBlock[valAddr];

        removeValidatorRank(valAddr);
    }

    function withdraw(address valAddr) public {
        _withdraw(valAddr, msg.sender);
    }

    function _calculateDelegationRewards(
        address valAddr,
        address delAddr,
        uint256 endingPeriod
    ) private view returns (uint256) {
        DelStartingInfo memory startingInfo = delStartingInfo[valAddr][delAddr];
        uint256 rewards = 0;
        for (uint256 i = 0; i < valSlashEvents[valAddr].length; i++) {
            ValSlashEvent memory slashEvent = valSlashEvents[valAddr][i];
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

    function _calculateDelegationRewardsBetween(
        address valAddr,
        uint256 startingPeriod,
        uint256 endingPeriod,
        uint256 stake
    ) private view returns (uint256) {
        ValHRewards memory starting = valHRewards[valAddr][startingPeriod];
        ValHRewards memory ending = valHRewards[valAddr][endingPeriod];
        uint256 difference = ending.cumulativeRewardRatio.sub(
            starting.cumulativeRewardRatio
        );
        return stake.mulTrun(difference);
    }

    function _incrementValidatorPeriod(address valAddr)
        private
        returns (uint256)
    {
        Validator memory val = vals[valsIdx[valAddr] - 1];

        ValCurrentReward storage rewards = valCurrentRewards[valAddr];
        uint256 previousPeriod = rewards.period - 1;
        uint256 current = 0;
        if (rewards.reward > 0) {
            current = rewards.reward.divTrun(val.tokens);
        }
        uint256 historical = valHRewards[valAddr][previousPeriod]
            .cumulativeRewardRatio;
        _decrementReferenceCount(valAddr, previousPeriod);
        valHRewards[valAddr].push(
            ValHRewards({
                cumulativeRewardRatio: historical.add(current),
                reference_count: 1
            })
        );
        rewards.period++;
        rewards.reward = 0;
        return previousPeriod.add(1);
    }

    function _decrementReferenceCount(address valAddr, uint256 period) private {
        valHRewards[valAddr][period].reference_count--;
        if (valHRewards[valAddr][period].reference_count == 0) {
            delete valHRewards[valAddr][period];
        }
    }

    function _incrementReferenceCount(address valAddr, uint256 period) private {
        valHRewards[valAddr][period].reference_count++;
    }

    function _initializeDelegation(address valAddr, address delAddr) private {
        uint256 delIndex = delsIdx[valAddr][delAddr] - 1;
        uint256 previousPeriod = valCurrentRewards[valAddr].period - 1;
        _incrementReferenceCount(valAddr, previousPeriod);
        delStartingInfo[valAddr][delAddr].height = block.number;
        delStartingInfo[valAddr][delAddr].previousPeriod = previousPeriod;
        uint256 shares = delegations[valAddr][delIndex].shares;
        uint256 stake = _tokenFromShare(valAddr, shares);
        delStartingInfo[valAddr][delAddr].stake = stake;
    }

    function _initializeValidator(address valAddr) private {
        valHRewards[valAddr].push(
            ValHRewards({reference_count: 1, cumulativeRewardRatio: 0})
        );
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

    function withdrawReward(address valAddr) public {
        require(valsIdx[valAddr] > 0, "validator not found");
        require(delsIdx[valAddr][msg.sender] > 0, "delegator not found");
        _withdrawRewards(valAddr, msg.sender);
        _initializeDelegation(valAddr, msg.sender);
    }

    function getDelegationRewards(address valAddr, address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 valIndex = valsIdx[valAddr];
        uint256 delIndex = delsIdx[valAddr][delAddr];
        require(valIndex > 0, "validator not found");
        require(delIndex > 0, "delegation not found");
        Validator memory val = vals[valIndex - 1];
        Delegation memory del = delegations[valAddr][delIndex - 1];
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
        uint256 valIndex = valsIdx[valAddr];
        require(valIndex > 0, "validator not found");
        uint256 commission = valAccumulatedCommission[valAddr];
        require(commission > 0, "no validator commission to reward");
        valAddr.transfer(commission);
        valAccumulatedCommission[valAddr] = 0;
        emit WithdrawCommissionReward(valAddr, commission);
    }

    function withdrawValidatorCommission() public {
        _withdrawValidatorCommission(msg.sender);
    }

    function getValidator(address valAddr)
        public
        view
        returns (uint256, uint256, bool)
    {
        uint256 valIndex = valsIdx[valAddr];
        require(valIndex > 0, "validator not found");
        Validator memory val = vals[valIndex - 1];
        return (val.tokens, val.delegationShares, val.jailed);
    }

    function getValidatorDelegations(address valAddr)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        require(valsIdx[valAddr] > 0, "validator not found");
        uint256 total = delegations[valAddr].length;
        address[] memory dels = new address[](total);
        uint256[] memory shares = new uint256[](total);
        for (uint256 i = 0; i < total; i++) {
            dels[i] = delegations[valAddr][i].owner;
            shares[i] = delegations[valAddr][i].shares;
        }
        return (dels, shares);
    }

    function getDelegation(address valAddr, address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 delIndex = delsIdx[valAddr][delAddr];
        require(delIndex > 0, "delegation not found");
        Delegation memory del = delegations[valAddr][delIndex - 1];
        return (del.shares);
    }

    function getDelegatorValidators(address delAddr)
        public
        view
        returns (address[] memory)
    {
        return delVals[delAddr];
    }

    function getValidatorCommission(address valAddr)
        public
        view
        returns (uint256)
    {
        return valAccumulatedCommission[valAddr];
    }

    function getAllDelegatorRewards(address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 total = delVals[delAddr].length;
        uint256 rewards = 0;
        for (uint256 i = 0; i < total; i++) {
            rewards += getDelegationRewards(delVals[delAddr][i], delAddr);
        }
        return rewards;
    }

    function getDelegatorStake(address valAddr, address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 delIndex = delsIdx[valAddr][delAddr];
        require(delIndex > 0, "delegation not found");
        Delegation memory del = delegations[valAddr][delIndex - 1];
        return _tokenFromShare(valAddr, del.shares);
    }

    function getAllDelegatorStake(address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 stake = 0;
        uint256 total = delVals[delAddr].length;
        for (uint256 i = 0; i < total; i++) {
            stake += getDelegatorStake(delVals[delAddr][i], delAddr);
        }
        return stake;
    }

    function _tokenFromShare(address valAddr, uint256 shares)
        private
        view
        returns (uint256)
    {
        uint256 valIndex = valsIdx[valAddr];
        Validator memory val = vals[valIndex - 1];
        return shares.mul(val.tokens).div(val.delegationShares);
    }

    function _shareFromToken(address valAddr, uint256 amount)
        private
        view
        returns (uint256)
    {
        uint256 valIndex = valsIdx[valAddr];
        Validator memory val = vals[valIndex - 1];
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

    function getValidatorSlashEvents(address valAddr)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256 total = valSlashEvents[valAddr].length;
        uint256[] memory fraction = new uint256[](total);
        uint256[] memory height = new uint256[](total);
        for (uint256 i = 0; i < total; i++) {
            fraction[i] = valSlashEvents[valAddr][i].fraction;
            height[i] = valSlashEvents[valAddr][i].height;
        }
        return (height, fraction);
    }

    function _doubleSign(
        address valAddr,
        uint256 votingPower,
        uint256 distributionHeight
    ) private {
        if (valsIdx[valAddr] == 0) return;

        // reason: doubleSign
        emit Slashed(valAddr, votingPower, 2);

        _slash(
            valAddr,
            distributionHeight - 1,
            votingPower,
            _params.slashFractionDoubleSign
        );
        _jail(valAddr);
        // // (Dec 31, 9999 - 23:59:59 GMT).
        valSigningInfos[valAddr].jailedUntil = 253402300799;
    }

    function doubleSign(
        address valAddr,
        uint256 votingPower,
        uint256 distributionHeight
    ) public {
        _doubleSign(valAddr, votingPower, distributionHeight);
    }

    function _validateSignature(
        address valAddr,
        uint256 votingPower,
        bool signed
    ) private {
        Validator storage val = vals[valsIdx[valAddr] - 1];
        ValSigningInfo storage signInfo = valSigningInfos[valAddr];
        uint256 index = signInfo.indexOffset % _params.signedBlockWindow;
        signInfo.indexOffset++;
        if (missedBlock[valAddr].length == index) {
            missedBlock[valAddr].push(false);
        }
        bool previous = missedBlock[valAddr][index];
        bool missed = !signed;
        if (!previous && missed) {
            signInfo.missedBlockCounter++;
            missedBlock[valAddr][index] = true;
        } else if (previous && !missed) {
            signInfo.missedBlockCounter--;
            missedBlock[valAddr][index] = false;
        }

        if (missed) {
            emit Liveness(valAddr, signInfo.missedBlockCounter, block.number);
        }

        uint256 minHeight = signInfo.startHeight + _params.signedBlockWindow;

        uint256 minSignedPerWindow = _params.signedBlockWindow.mulTrun(
            _params.minSignedPerWindow
        );
        uint256 maxMissed = _params.signedBlockWindow - minSignedPerWindow;
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
                signInfo.missedBlockCounter = 0;
                signInfo.indexOffset = 0;
                delete missedBlock[valAddr];
            }
        }
    }

    function _allocateTokens(
        uint256 sumPreviousPrecommitPower,
        uint256 totalPreviousVotingPower,
        address previousProposer,
        address[] memory addrs,
        uint256[] memory powers
    ) private {
        uint256 previousFractionVotes = sumPreviousPrecommitPower.divTrun(
            totalPreviousVotingPower
        );
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
            _allocateTokensToValidator(addrs[i], rewards);
        }
    }

    function _allocateTokensToValidator(address valAddr, uint256 rewards)
        private
    {
        uint256 commission = rewards.mulTrun(
            vals[valsIdx[valAddr] - 1].commission.rate
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

    function finalizeCommit(
        address[] memory addrs,
        uint256[] memory powers,
        bool[] memory signed
    ) public onlyRoot {
        _finalizeCommit(addrs, powers, signed);
    }

    function setPreviousProposer(address previousProposer) public onlyRoot {
        _previousProposer = previousProposer;
    }

    function getValidators()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 total = vals.length;
        address[] memory valAddrs = new address[](total);
        uint256[] memory powers = new uint256[](total);

        for (uint256 i = 0; i < vals.length; i++) {
            valAddrs[i] = vals[i].owner;
            powers[i] = vals[i].tokens.div(powerReduction);
        }
        return (valAddrs, powers);
    }

    function getMissedBlock(address valAddr)
        public
        view
        returns (bool[] memory)
    {
        return missedBlock[valAddr];
    }

    // Mint
    //  --------------------------------------------------

    // @dev mints new tokens for the previous block. Returns fee collected
    function mint() public onlyRoot returns (uint256) {
        // recalculate inflation rate
        nextInflationRate();
        // recalculate annual provisions
        nextAnnualProvisions();
        // update fee collected
        _feesCollected = getBlockProvision();
        totalSupply += _feesCollected;
        emit Minted(_feesCollected);
        return _feesCollected;
    }

    function setInflation(uint256 _inflation) public onlyRoot {
        inflation = _inflation;
    }

    function nextInflationRate() private {
        uint256 bondedRatio = totalBonded.divTrun(totalSupply);
        if (bondedRatio < _params.goalBonded) {
            uint256 inflationRateChangePerYear = oneDec
                .sub(bondedRatio.divTrun(_params.goalBonded))
                .mulTrun(_params.inflationRateChange);
            uint256 inflationRateChange = inflationRateChangePerYear.div(
                _params.blocksPerYear
            );
            inflation = inflation.add(inflationRateChange);
        } else {
            uint256 inflationRateChangePerYear = bondedRatio
                .divTrun(_params.goalBonded)
                .sub(oneDec)
                .mulTrun(_params.inflationRateChange);
            uint256 inflationRateChange = inflationRateChangePerYear.div(
                _params.blocksPerYear
            );
            if (inflation > inflationRateChange) {
                inflation = inflation.sub(inflationRateChange);
            } else {
                inflation = 0;
            }
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

    function setAnnualProvision(uint256 _annualProvision) public onlyRoot {
        annualProvision = _annualProvision;
    }

    function getBlockProvision() public view returns (uint256) {
        return annualProvision.div(_params.blocksPerYear);
    }

    function setTotalSupply(uint256 amount) public onlyRoot {
        totalSupply = amount;
    }

    function getInflation() public view returns (uint256) {
        return inflation;
    }

    // validator rank
    function addValidatorRank(address valAddr) private {
        uint256 idx = validatorRankIndex[valAddr];
        if (idx == 0) {
            if (valsRank.length == 500) {
                address last = valsRank[valsRank.length - 1];
                if (
                    vals[valsIdx[valAddr] - 1].tokens <
                    vals[valsIdx[last] - 1].tokens
                ) {
                    return;
                }
                delete validatorRankIndex[last];
                valsRank[valsRank.length - 1] = valAddr;
                validatorRankIndex[valAddr] = valsRank.length;
            } else {
                valsRank.push(valAddr);
                validatorRankIndex[valAddr] = valsRank.length;
            }
        }
        _needSort = true;
    }

    function removeValidatorRank(address valAddr) private {
        uint256 rankIndex = validatorRankIndex[valAddr];
        if (rankIndex > 0) {
            uint256 lastIndex = valsRank.length - 1;
            address last = valsRank[lastIndex];
            valsRank[rankIndex - 1] = last;
            validatorRankIndex[last] = rankIndex;
            delete validatorRankIndex[valAddr];
            valsRank.pop();
            _needSort = true;
        }
    }

    function getValidatorTokenByRank(uint256 rank)
        private
        view
        returns (uint256)
    {
        return vals[valsIdx[valsRank[rank]] - 1].tokens.div(powerReduction);
    }

    function _sortValidatorRank(int256 left, int256 right) internal {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = getValidatorTokenByRank(
            uint256(left + (right - left) / 2)
        );
        while (i <= j) {
            while (getValidatorTokenByRank(uint256(i)) > pivot) i++;
            while (pivot > getValidatorTokenByRank(uint256(j))) j--;
            if (i <= j) {
                address tmp = valsRank[uint256(i)];
                valsRank[uint256(i)] = valsRank[uint256(j)];
                valsRank[uint256(j)] = tmp;

                validatorRankIndex[tmp] = uint256(j + 1);
                validatorRankIndex[valsRank[uint256(i)]] = uint256(i + 1);

                i++;
                j--;
            }
        }
        if (left < j) _sortValidatorRank(left, j);
        if (i < right) _sortValidatorRank(i, right);
    }

    function applyAndReturnValidatorSets()
        public
        onlyRoot
        returns (address[] memory, uint256[] memory)
    {
        if (_needSort && valsRank.length > 0) {
            _sortValidatorRank(0, int256(valsRank.length - 1));
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
        if (maxVal > valsRank.length) {
            maxVal = valsRank.length;
        }
        address[] memory valAddrs = new address[](maxVal);
        uint256[] memory powers = new uint256[](maxVal);

        for (uint256 i = 0; i < maxVal; i++) {
            valAddrs[i] = valsRank[i];
            powers[i] = getValidatorPower(valsRank[i]);
        }
        return (valAddrs, powers);
    }

    function getValidatorPower(address valAddr) public view returns (uint256) {
        return vals[valsIdx[valAddr] - 1].tokens.div(powerReduction);
    }

    // slashing
    function _unjail(address valAddr) private {
        require(valsIdx[valAddr] > 0, "validator not found");
        uint256 valIndex = valsIdx[valAddr] - 1;
        Validator storage val = vals[valIndex];
        require(val.jailed, "validator not jailed");
        uint256 jailedUntil = valSigningInfos[valAddr].jailedUntil;
        // solhint-disable-next-line not-rely-on-time
        require(jailedUntil < block.timestamp, "validator jailed");
        uint256 delIndex = delsIdx[valAddr][valAddr] - 1;
        Delegation storage del = delegations[valAddr][delIndex];
        uint256 tokens = _tokenFromShare(valAddr, del.shares);
        require(tokens > val.minSelfDelegation, "self delegation too low to unjail");

        valSigningInfos[valAddr].jailedUntil = 0;
        val.jailed = false;
        addValidatorRank(valAddr);
    }

    function unjail() public {
        _unjail(msg.sender);
        emit UnJail(msg.sender);
    }
}
