pragma solidity >=0.4.21 <0.7.0;
import {SafeMath} from "./Safemath.sol";


contract Staking {
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

    struct ValidatorCommission {
        uint256 rate;
        uint256 maxRate;
        uint256 maxChangeRate;
    }

    struct Validator {
        address owner;
        uint256 tokens;
        uint256 delegationShares;
        bool jailed;
        ValidatorCommission commission;
        uint256 minSelfDelegation;
        uint256 updateTime;
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
        uint256 reference_count;
    }

    struct ValidatorSigningInfo {
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
        uint256 maxMissed;
        uint256 downtimeJailDuration;
        uint256 slashFractionDowntime;
        uint256 unbondingTime;
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
    mapping(address => mapping(address => uint256)) delegationsIndex;
    mapping(address => mapping(address => UBDEntry[])) unbondingEntries;
    mapping(address => mapping(address => DelegatorStartingInfo)) delegatorStartingInfo;
    mapping(address => ValidatorSlashEvent[]) validatorSlashEvents;
    mapping(address => ValidatorCurrentReward) validatorCurrentRewards;
    mapping(address => ValidatorHistoricalRewards[]) validatorHistoricalRewards;
    mapping(address => bool[1000]) validatorMissedBlockBitArray;
    mapping(address => ValidatorSigningInfo) validatorSigningInfos;
    mapping(address => uint256) validatorAccumulatedCommission;
    mapping(address => Delegation[]) delegations;
    mapping(address => uint256) validatorsIndex;
    mapping(address => address[]) delegatorValidators;
    mapping(address => mapping(address => uint256)) delegatorValidatorsIndex;

    // sort
    address[] validatorsRank;
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

    constructor() public {
        _params = Params({
            maxValidators: 100,
            maxMissed: 10000,
            downtimeJailDuration: 600,
            baseProposerReward: 1 * 10**16,
            bonusProposerReward: 4 * 10**16,
            slashFractionDowntime: 1 * 10**14,
            unbondingTime: 1814400,
            slashFractionDoubleSign: 5 * 10**16,
            signedBlockWindown: 1000,
            minSignedPerWindown: 10,
            inflationRateChange: 13 * 10**16,
            goalBonded: 67 * 10**16,
            blocksPerYear: 6311520,
            inflationMax: 20 * 10**16,
            inflationMin: 7 * 10**16
        });
    }

    modifier onlyRoot() {
        //require (msg.sender == root, "permission denied");
        _;
    }

    function setRoot(address newRoot) public {
        if (_root != address(0x0)) {
            require(msg.sender == _root, "");
        }
        _root = newRoot;
    }

    function setParams(
        uint256 maxValidators,
        uint256 maxMissed,
        uint256 downtimeJailDuration,
        uint256 baseProposerReward,
        uint256 bonusProposerReward,
        uint256 slashFractionDowntime,
        uint256 unbondingTime,
        uint256 slashFractionDoubleSign
    ) public onlyRoot {
        if (maxValidators > 0) {
            _params.maxValidators = maxValidators;
        }
        if (maxMissed > 0) {
            _params.maxMissed = maxMissed;
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
    }

    function _createValidator(
        address payable valAddr,
        uint256 amount,
        uint256 rate,
        uint256 maxRate,
        uint256 maxChangeRate,
        uint256 minSelfDelegation
    ) private {
        require(validatorsIndex[valAddr] == 0, "");
        require(amount > 0, "");
        require(amount >= minSelfDelegation, "");
        require(maxRate <= oneDec, "");
        require(maxChangeRate <= maxRate, "");
        require(rate <= maxRate, "");

        ValidatorCommission memory commission = ValidatorCommission({
            rate: rate,
            maxRate: maxRate,
            maxChangeRate: maxChangeRate
        });
        validators.push(
            Validator({
                owner: valAddr,
                tokens: 0,
                delegationShares: 0,
                jailed: false,
                commission: commission,
                minSelfDelegation: minSelfDelegation,
                updateTime: block.timestamp
            })
        );
        validatorsIndex[valAddr] = validators.length;
        _afterValidatorCreated(valAddr);
        _delegate(valAddr, valAddr, amount);
    }

    function updateValidator(uint256 commissionRate, uint256 minSelfDelegation)
        public
    {
        require(validatorsIndex[msg.sender] > 0, "validator not found");
        Validator storage val = validators[validatorsIndex[msg.sender] - 1];
        if (commissionRate > 0) {
            require((block.timestamp - val.updateTime) > 86400, "");
            require(commissionRate < val.commission.maxRate, "");
            require(
                commissionRate.sub(val.commission.rate) <
                    val.commission.maxChangeRate,
                ""
            );
        }
        if (minSelfDelegation > 0) {
            require(minSelfDelegation > val.minSelfDelegation, "");
            require(minSelfDelegation < val.tokens, "");
            val.minSelfDelegation = minSelfDelegation;
        }

        if (commissionRate > 0) {
            val.commission.rate = commissionRate;
            val.updateTime = block.timestamp;
        }
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
        uint256 delIndex = delegationsIndex[valAddr][delAddr];
        // add delegation if not exists;
        if (delIndex == 0) {
            delegations[valAddr].push(Delegation({owner: delAddr, shares: 0}));
            delIndex = delegations[valAddr].length;
            delegationsIndex[valAddr][delAddr] = delIndex;

            // delegator validators index
            delegatorValidators[delAddr].push(valAddr);
            delegatorValidatorsIndex[delAddr][valAddr] = delegatorValidators[delAddr]
                .length;

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
        Validator storage val = validators[validatorsIndex[valAddr] - 1];
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
        require(validatorsIndex[valAddr] > 0, "validator not found");
        require(msg.value > 0, "invalid delegation amount");
        _delegate(msg.sender, valAddr, msg.value);
    }

    function _undelegate(
        address valAddr,
        address payable delAddr,
        uint256 amount
    ) private {
        require(
            unbondingEntries[valAddr][delAddr].length < 7,
            "too many unbonding delegation entries"
        );
        uint256 delegationIndex = delegationsIndex[valAddr][delAddr];
        require(delegationIndex > 0, "delegation not found");
        _beforeDelegationSharesModified(valAddr, delAddr);

        Validator storage val = validators[validatorsIndex[valAddr] - 1];
        Delegation storage del = delegations[valAddr][delegationIndex - 1];
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
        } else {
            addValidatorRank(valAddr);
        }

        unbondingEntries[valAddr][delAddr].push(
            UBDEntry({
                completionTime: block.timestamp.add(_params.unbondingTime),
                blockHeight: block.number,
                amount: amountRemoved
            })
        );
    }

    function _removeDelShares(address valAddr, uint256 shares)
        private
        returns (uint256)
    {
        Validator storage val = validators[validatorsIndex[valAddr] - 1];
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
        validators[validatorsIndex[valAddr] - 1].jailed = true;
        removeValidatorRank(valAddr);
    }

    function _slash(
        address valAddr,
        uint256 infrationHeight,
        uint256 power,
        uint256 slashFactor
    ) private {
        require(infrationHeight <= block.number, "");
        Validator storage val = validators[validatorsIndex[valAddr] - 1];
        uint256 slashAmount = power.mul(powerReduction).mulTrun(slashFactor);
        if (infrationHeight < block.number) {
            for (uint256 i = 0; i < delegations[valAddr].length; i++) {

                    UBDEntry[] storage entries
                 = unbondingEntries[valAddr][delegations[valAddr][i].owner];
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
        val.tokens -= slashAmount;
        _updateValidatorSlashFraction(valAddr, slashFactor);
        _burn(slashAmount);
    }

    function _burn(uint256 amount) private {
        totalBonded -= amount;
        totalSupply -= amount;
    }

    function _updateValidatorSlashFraction(address valAddr, uint256 fraction)
        private
    {
        uint256 newPeriod = _incrementValidatorPeriod(valAddr);
        _incrementReferenceCount(valAddr, newPeriod);
        validatorSlashEvents[valAddr].push(
            ValidatorSlashEvent({
                validatorPeriod: newPeriod,
                fraction: fraction,
                height: block.number
            })
        );
    }

    function _withdraw(address valAddr, address payable delAddr) private {
        UBDEntry[] storage entries = unbondingEntries[valAddr][delAddr];
        uint256 amount = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].completionTime < block.timestamp) {
                amount += entries[i].amount;
                entries[i] = entries[entries.length - 1];
                entries.pop();
                i++;
            }
        }
        require(amount > 0, "no unbonding amount to withdraw");
        delAddr.transfer(amount);
        totalBonded -= amount;
    }

    function _removeDelegation(address valAddr, address delAddr) private {
        // delete delegation and delegation index
        uint256 delegationIndex = delegationsIndex[valAddr][delAddr];
        uint256 lastDelegationIndex = delegations[valAddr].length;


            Delegation memory lastDelegation
         = delegations[valAddr][lastDelegationIndex - 1];
        delegations[valAddr][delegationIndex - 1] = lastDelegation;
        delegations[valAddr].pop();
        delegationsIndex[valAddr][lastDelegation.owner] = delegationIndex;

        // delete other info
        delete delegationsIndex[valAddr][delAddr];
        delete delegatorStartingInfo[valAddr][delAddr];

        // delete delegator validator index
        uint256 delValIndex = delegatorValidatorsIndex[delAddr][valAddr];
        delegatorValidators[delAddr][delValIndex -
            1] = delegatorValidators[delAddr][delegatorValidators[delAddr]
            .length - 1];
        delegatorValidators[delAddr].pop();
        delete delegatorValidatorsIndex[delAddr][valAddr];
    }

    function _removeValidator(address valAddr) private {
        // remove validator
        uint256 validatorIndex = validatorsIndex[valAddr];
        uint256 lastValidatorIndex = validators.length;
        Validator memory lastValidator = validators[lastValidatorIndex - 1];
        validators[validatorIndex - 1] = lastValidator;
        validators.pop();
        validatorsIndex[lastValidator.owner] = validatorIndex;
        delete validatorsIndex[valAddr];

        // remove other index
        delete validatorSlashEvents[valAddr];
        delete validatorAccumulatedCommission[valAddr];
        delete validatorHistoricalRewards[valAddr];
        delete validatorCurrentRewards[valAddr];
        
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

            DelegatorStartingInfo memory startingInfo
         = delegatorStartingInfo[valAddr][delAddr];
        uint256 rewards = 0;
        for (uint256 i = 0; i < validatorSlashEvents[valAddr].length; i++) {

                ValidatorSlashEvent memory slashEvent
             = validatorSlashEvents[valAddr][i];
            if (
                slashEvent.height > startingInfo.height &&
                slashEvent.height < block.number
            ) {
                endingPeriod = slashEvent.validatorPeriod;
                if (endingPeriod > startingInfo.previousPeriod) {
                    rewards += _calculateDelegationRewardsBetween(
                        valAddr,
                        startingInfo.previousPeriod,
                        slashEvent.validatorPeriod,
                        startingInfo.stake
                    );
                    startingInfo.stake = startingInfo.stake.mulTrun(
                        slashEvent.fraction
                    );
                    startingInfo.previousPeriod = endingPeriod;
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

            ValidatorHistoricalRewards memory starting
         = validatorHistoricalRewards[valAddr][startingPeriod];


            ValidatorHistoricalRewards memory ending
         = validatorHistoricalRewards[valAddr][endingPeriod];
        uint256 difference = ending.cumulativeRewardRatio.sub(
            starting.cumulativeRewardRatio
        );
        return stake.mulTrun(difference);
    }

    function _incrementValidatorPeriod(address valAddr)
        private
        returns (uint256)
    {
        Validator memory val = validators[validatorsIndex[valAddr] - 1];


            ValidatorCurrentReward storage rewards
         = validatorCurrentRewards[valAddr];
        uint256 previousPeriod = rewards.period - 1;
        uint256 current = 0;
        if (rewards.reward > 0) {
            current = rewards.reward.divTrun(val.tokens);
        }
        uint256 historical = validatorHistoricalRewards[valAddr][previousPeriod]
            .cumulativeRewardRatio;
        _decrementReferenceCount(valAddr, rewards.period - 1);
        validatorHistoricalRewards[valAddr].push(
            ValidatorHistoricalRewards({
                cumulativeRewardRatio: historical.add(current),
                reference_count: 1
            })
        );
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
        uint256 delegationIndex = delegationsIndex[valAddr][delAddr] - 1;
        uint256 previousPeriod = validatorCurrentRewards[valAddr].period - 1;
        _incrementReferenceCount(valAddr, previousPeriod);
        delegatorStartingInfo[valAddr][delAddr].height = block.number;
        delegatorStartingInfo[valAddr][delAddr].previousPeriod = previousPeriod;
        uint256 stake = _tokenFromShare(
            valAddr,
            delegations[valAddr][delegationIndex].shares
        );
        delegatorStartingInfo[valAddr][delAddr].stake = stake;
    }

    function _initializeValidator(address valAddr) private {
        validatorHistoricalRewards[valAddr].push(
            ValidatorHistoricalRewards({
                reference_count: 1,
                cumulativeRewardRatio: 0
            })
        );
        validatorCurrentRewards[valAddr].period = 1;
        validatorCurrentRewards[valAddr].reward = 0;
        validatorAccumulatedCommission[valAddr] = 0;
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
            delegatorStartingInfo[valAddr][delAddr].previousPeriod
        );
        delete delegatorStartingInfo[valAddr][delAddr];
        delAddr.transfer(rewards);
    }

    function withdrawReward(address valAddr) public {
        require(validatorsIndex[valAddr] > 0, "validator not found");
        require(
            delegationsIndex[valAddr][msg.sender] > 0,
            "delegator not found"
        );
        _withdrawRewards(valAddr, msg.sender);
        _initializeDelegation(valAddr, msg.sender);
    }

    function getDelegationRewards(address valAddr, address delAddr)
        public
        view
        returns (uint256)
    {
        require(validatorsIndex[valAddr] > 0, "validator not found");
        require(delegationsIndex[valAddr][delAddr] > 0, "delegation not found");
        Validator memory val = validators[validatorsIndex[valAddr] - 1];


            Delegation memory del
         = delegations[valAddr][delegationsIndex[valAddr][delAddr] - 1];
        uint256 rewards = _calculateDelegationRewards(
            valAddr,
            delAddr,
            validatorCurrentRewards[valAddr].period
        );
        // current reward
        rewards += _tokenFromShare(valAddr, del.shares).mulTrun(
            validatorCurrentRewards[valAddr].reward.divTrun(val.tokens)
        );
        return rewards;
    }

    function _withdrawValidatorCommission(address payable valAddr) private {
        require(
            validators[validatorsIndex[valAddr] - 1].owner != address(0x0),
            "validator does not exists"
        );
        require(
            validatorAccumulatedCommission[valAddr] > 0,
            "no validator commission to reward"
        );
        valAddr.transfer(validatorAccumulatedCommission[valAddr]);
        validatorAccumulatedCommission[valAddr] = 0;
    }

    function withdrawValidatorCommission() public {
        _withdrawValidatorCommission(msg.sender);
    }

    function getValidator(address valAddr)
        public
        view
        returns (uint256, uint256, bool)
    {
        require(validatorsIndex[valAddr] > 0, "validator not found");
        uint256 valIndex = validatorsIndex[valAddr] - 1;
        return (
            validators[valIndex].tokens,
            validators[valIndex].delegationShares,
            validators[valIndex].jailed
        );
    }

    function getValidatorDelegations(address valAddr)
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        require(validatorsIndex[valAddr] > 0, "validator not found");
        address[] memory dels = new address[](delegations[valAddr].length);
        uint256[] memory shares = new uint256[](delegations[valAddr].length);
        for (uint256 i = 0; i < delegations[valAddr].length; i++) {
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
        uint256 delIndex = delegationsIndex[valAddr][delAddr];
        require(delIndex > 0, "delegation not found");
        Delegation memory del = delegations[valAddr][delIndex - 1];
        return (del.shares);
    }

    function getDelegatorValidators(address delAddr)
        public
        view
        returns (address[] memory)
    {
        return delegatorValidators[delAddr];
    }

    function getValidatorCommission(address valAddr)
        public
        view
        returns (uint256)
    {
        return validatorAccumulatedCommission[valAddr];
    }

    function getAllDelegatorRewards(address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 rewards = 0;
        for (uint256 i = 0; i < delegatorValidators[delAddr].length; i++) {
            rewards += getDelegationRewards(
                delegatorValidators[delAddr][i],
                delAddr
            );
        }
        return rewards;
    }

    function getDelegatorStake(address valAddr, address delAddr)
        public
        view
        returns (uint256)
    {
        uint256 delIndex = delegationsIndex[valAddr][delAddr];
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
        for (uint256 i = 0; i < delegatorValidators[delAddr].length; i++) {
            stake += getDelegatorStake(
                delegatorValidators[delAddr][i],
                delAddr
            );
        }
        return stake;
    }

    function _tokenFromShare(address valAddr, uint256 shares)
        private
        view
        returns (uint256)
    {
        uint256 valIndex = validatorsIndex[valAddr];
        Validator memory val = validators[valIndex - 1];
        return shares.mul(val.tokens).div(val.delegationShares);
    }

    function _shareFromToken(address valAddr, uint256 amount)
        private
        view
        returns (uint256)
    {
        uint256 valIndex = validatorsIndex[valAddr];
        Validator memory val = validators[valIndex - 1];
        return val.delegationShares.mul(amount).div(val.tokens);
    }

    function getUBDEntries(address valAddr, address delAddr)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256[] memory balances = new uint256[](
            unbondingEntries[valAddr][delAddr].length
        );
        uint256[] memory completionTime = new uint256[](
            unbondingEntries[valAddr][delAddr].length
        );
        for (
            uint256 i = 0;
            i < unbondingEntries[valAddr][delAddr].length;
            i++
        ) {
            completionTime[i] = unbondingEntries[valAddr][delAddr][i]
                .completionTime;
            balances[i] = unbondingEntries[valAddr][delAddr][i].amount;
        }
        return (balances, completionTime);
    }

    function getValidatorSlashEvents(address valAddr)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256[] memory fraction = new uint256[](
            validatorSlashEvents[valAddr].length
        );
        uint256[] memory height = new uint256[](
            validatorSlashEvents[valAddr].length
        );
        for (uint256 i = 0; i < validatorSlashEvents[valAddr].length; i++) {
            fraction[i] = validatorSlashEvents[valAddr][i].fraction;
            height[i] = validatorSlashEvents[valAddr][i].height;
        }
        return (height, fraction);
    }

    function _doubleSign(
        address valAddr,
        uint256 votingPower,
        uint256 distributionHeight
    ) private {
        if (validatorsIndex[valAddr] == 0) return;
        _slash(
            valAddr,
            distributionHeight - 1,
            votingPower,
            _params.slashFractionDoubleSign
        );
        _jail(valAddr);
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
        Validator storage val = validators[validatorsIndex[valAddr] - 1];
        ValidatorSigningInfo storage signInfo = validatorSigningInfos[valAddr];
        uint256 index = signInfo.indexOffset % _params.signedBlockWindown;
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
        uint256 maxMissed = _params.signedBlockWindown -
            _params.minSignedPerWindown;
        if (
            block.number > minHeight && signInfo.missedBlockCounter > maxMissed
        ) {
            if (!val.jailed) {
                _slash(
                    valAddr,
                    block.number - 2,
                    votingPower,
                    _params.slashFractionDowntime
                );
                _jail(valAddr);
                signInfo.jailedUntil = block.timestamp.add(
                    _params.downtimeJailDuration
                );
                signInfo.missedBlockCounter = 0;
                signInfo.indexOffset = 0;
                delete validatorMissedBlockBitArray[valAddr];
            }
        }
    }

    function _allocateTokens(
        uint256 sumPreviousPrecommitPower,
        uint256 totalPreviousVotingPower,
        address previousProposer,
        address[] memory vals,
        uint256[] memory powers
    ) private {
        uint256 previousFractionVotes = sumPreviousPrecommitPower.divTrun(
            totalPreviousVotingPower
        );
        uint256 proposerMultiplier = _params.baseProposerReward.add(
            _params.baseProposerReward.mulTrun(previousFractionVotes)
        );
        uint256 proposerReward = _feesCollected.mulTrun(proposerMultiplier);
        _allocateTokensToValidator(previousProposer, proposerReward);
        _feesCollected -= proposerReward;

        uint256 voteMultiplier = oneDec.sub(proposerMultiplier);
        for (uint256 i = 0; i < vals.length; i++) {
            uint256 powerFraction = powers[i].divTrun(totalPreviousVotingPower);
            uint256 rewards = _feesCollected.mulTrun(voteMultiplier).mulTrun(
                powerFraction
            );
            _allocateTokensToValidator(vals[0], rewards);
            _feesCollected -= rewards;
        }
    }

    function _allocateTokensToValidator(address valAddr, uint256 rewards)
        private
    {
        uint256 commission = rewards.mulTrun(
            validators[validatorsIndex[valAddr] - 1].commission.rate
        );
        uint256 shared = rewards.sub(commission);
        validatorAccumulatedCommission[valAddr] += commission;
        validatorCurrentRewards[valAddr].reward += shared;
    }

    function _finalizeCommit(
        address[] memory vals,
        uint256[] memory powers,
        bool[] memory signed
    ) private {
        uint256 previousTotalPower = 0;
        uint256 sumPreviousPrecommitPower = 0;
        for (uint256 i = 0; i < powers.length; i++) {
            _validateSignature(vals[i], powers[i], signed[i]);
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
                vals,
                powers
            );
        }
        _previousProposer = block.coinbase;
    }

    function finalizeCommit(
        address[] memory vals,
        uint256[] memory powers,
        bool[] memory signed
    ) public onlyRoot {
        _finalizeCommit(vals, powers, signed);
    }

    function getValidators()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory vals = new address[](validators.length);
        uint256[] memory powers = new uint256[](validators.length);

        for (uint256 i = 0; i < validators.length; i++) {
            vals[i] = validators[i].owner;
            powers[i] = validators[i].tokens.div(powerReduction);
        }
        return (vals, powers);
    }

    function getMissedBlock(address valAddr)
        public
        view
        returns (bool[1000] memory)
    {
        return validatorMissedBlockBitArray[valAddr];
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
        return _feesCollected;
    }

    function nextInflationRate() private {
        uint256 bondedRatio = totalBonded.divTrun(totalSupply);
        uint256 inflationChangeRatePerYear = 0;
        uint256 inflationRateChange = 0;
        if (bondedRatio.divTrun(_params.goalBonded) > oneDec) {
            inflationChangeRatePerYear = bondedRatio
                .divTrun(_params.goalBonded)
                .sub(oneDec)
                .mul(_params.inflationRateChange);
            inflationRateChange = inflationRateChange.div(
                _params.blocksPerYear
            );
            if (inflationRateChange < inflation) {
                inflation = inflation.sub(inflationRateChange);
            } else {
                inflation = 0;
            }
        } else {
            inflationChangeRatePerYear = oneDec
                .sub(bondedRatio.divTrun(_params.goalBonded))
                .mul(_params.inflationRateChange);
            inflationRateChange = inflationRateChange.div(
                _params.blocksPerYear
            );
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

    function getBlockProvision() public view returns (uint256) {
        return annualProvision.div(_params.blocksPerYear);
    }

   // validator rank
    function addValidatorRank(address valAddr) private {
        if (validatorRankIndex[valAddr] == 0) {
            if (validatorsRank.length == 500) {
                address last = validatorsRank[validatorsRank.length - 1];
                delete validatorRankIndex[last];
                validatorsRank[validatorsRank.length - 1] = valAddr;
                validatorRankIndex[valAddr] = validatorsRank.length;
            } else {
                validatorsRank.push(valAddr);
                validatorRankIndex[valAddr] = validatorsRank.length;
            }
        }
        _needSort = true;
    }

    function removeValidatorRank(address valAddr) private {
        uint rankIndex = validatorRankIndex[valAddr];
        if (rankIndex > 0) {
            uint lastIndex = validatorsRank.length - 1;
            address last = validatorsRank[lastIndex];
            validatorsRank[rankIndex - 1] = last;
            validatorRankIndex[last] = rankIndex;
            delete validatorRankIndex[valAddr];
            validatorsRank.pop();
            _needSort = true;
        }
    }

    function getValidatorTokenByRank(uint256 rank)
        private
        view
        returns (uint256)
    {
        return
            validators[validatorsIndex[validatorsRank[rank]] - 1].tokens.div(
                powerReduction
            );
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
                address tmp = validatorsRank[uint256(i)];
                validatorsRank[uint256(i)] = validatorsRank[uint256(j)];
                validatorsRank[uint256(j)] = tmp;

                validatorRankIndex[tmp] = uint256(j + 1);
                validatorRankIndex[validatorsRank[uint256(i)]] = uint256(i + 1);

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
        if (_needSort && validatorsRank.length > 0) {
            _sortValidatorRank(0, int256(validatorsRank.length - 1));
            _needSort = false;
        }
        return getValidatorSets();
    }

    function getValidatorSets()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 maxValidators = _params.maxValidators;
        if (maxValidators > validatorsRank.length) {
            maxValidators = validatorsRank.length;
        }
        address[] memory vals = new address[](maxValidators);
        uint256[] memory powers = new uint256[](maxValidators);

        for (uint256 i = 0; i < maxValidators; i++) {
            vals[i] = validatorsRank[i];
            powers[i] = validators[validatorsIndex[vals[i]] - 1].tokens.div(
                powerReduction
            );
        }
        return (vals, powers);
    }
}
