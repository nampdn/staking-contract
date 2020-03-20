pragma solidity >=0.4.21 <0.7.0;
import {SafeMath} from "./Safemath.sol";

contract Staking {
    using SafeMath for uint256;
    uint256 powerReduction = 1 * 10**6;
    uint256 onDec = 1 * 10**18;
    struct Validator {
        address operatorAddress;
        uint256 tokens;
        bool jailed;
        Commission commission;
        uint256 rewards;
        uint256 commissionRewards;
        uint256 updateTime;
        uint256 cumulativeRewardRatio;
        uint256 missedBlockCounter;
        uint256 jailedUntil;
        uint256 cumulativeSlashRatio;
        uint256 minselfDelegation;
        uint256 rank;
        uint256 unboudingEntryCount;
        Description description;
    }

    struct Commission {
        uint256 rate;
        uint256 maxRate;
        uint256 maxChangeRate;
    }

    struct Description {
        string name;
        string identity;
        string website;
        string contact;
    }

    struct Delegation {
        uint256 stake;
        uint256 cumulativeRewardRatio;
        uint256 cumulativeSlashRatio;
        UnbondingDelegationEntry[] ubdEntries;
    }

    struct UnbondingDelegationEntry {
        uint256 completionTime;
        uint256 balance;
        uint256 cumulativeSlashRatio;
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

        uint256 inflationRateChange;
        uint256 goalBonded;
        uint256 blocksPerYear;
        uint256 inflationMax;
        uint256 inflationMin;
    }

    address previousProposerAddr;
    mapping(address => Validator) validators;
    mapping(address => mapping(address => Delegation)) delegations;
    address[] public validatorByRank;

    Params params;

    
    uint256 totalSupply = 5000000000 * 10 * 6;
    uint256 inflation = 0;
    uint256 totalBonded = 0;
    uint256 annualProvision = 0;

    modifier onlyRoot() {
        _;
    }

    constructor(
        uint256 maxValidators,
        uint256 maxMissed,
        uint256 downtimeJailDuration,
        uint256 baseProposerReward,
        uint256 bonusProposerReward,
        uint256 slashFractionDowntime,
        uint256 unboudingTime,
        uint256 slashFractionDoubleSign
    ) public {
        params = Params({
            maxValidators: maxValidators,
            maxMissed: maxMissed,
            downtimeJailDuration: downtimeJailDuration,
            baseProposerReward: baseProposerReward,
            bonusProposerReward: bonusProposerReward,
            slashFractionDowntime: slashFractionDowntime,
            unboudingTime: unboudingTime,
            slashFractionDoubleSign: slashFractionDoubleSign
        });
    }

    function setParams(
        uint256 maxValidators,
        uint256 maxMissed,
        uint256 downtimeJailDuration,
        uint256 baseProposerReward,
        uint256 bonusProposerReward,
        uint256 slashFractionDowntime,
        uint256 unboudingTime,
        uint256 slashFractionDoubleSign
    ) public onlyRoot {
        if (maxValidators > 0) {
            params.maxValidators = maxValidators;
        }
        if (maxMissed > 0) {
            params.maxMissed = maxMissed;
        }
        if (downtimeJailDuration > 0) {
            params.downtimeJailDuration = downtimeJailDuration;
        }
        if (baseProposerReward > 0) {
            params.baseProposerReward = baseProposerReward;
        }
        if (bonusProposerReward > 0) {
            params.bonusProposerReward = bonusProposerReward;
        }
        if (slashFractionDowntime > 0) {
            params.slashFractionDowntime = slashFractionDowntime;
        }
        if (unboudingTime > 0) {
            params.unboudingTime = unboudingTime;
        }
        if (slashFractionDoubleSign > 0) {
            params.slashFractionDoubleSign = slashFractionDoubleSign;
        }
    }

    function tokenByRank(uint256 idx) private view returns (uint256) {
        if (validators[validatorByRank[idx]].jailed) {
            return 0;
        }
        return validators[validatorByRank[idx]].tokens;
    }

    function sortRankByVotingPower(uint idx) private {
        _sortRankByVotingPower(idx);
        cleanValidatorByRankArr();
    }
    function cleanValidatorByRankArr() private {
        for (uint256 i = validatorByRank.length - 1; i >= 0; i--) {
            if (tokenByRank(i) > 0) break;
            validatorByRank.pop();
        }
    }

    function _moveValRank(uint256 i1, uint256 i2) private {
        validators[validatorByRank[i1]].rank = i2;
        validators[validatorByRank[i2]].rank = i1;
        address tmp = validatorByRank[i1];
        validatorByRank[i1] = validatorByRank[i2];
        validatorByRank[i2] = tmp;
    }

    function _sortRankByVotingPower(uint256 idx) private {
        for (uint256 i = idx; i > 0; i--) {
            if (tokenByRank(i) <= tokenByRank(i - 1)) {
                break;
            }
            _moveValRank(i, i - 1);
        }

        for (uint256 i = idx; i < validatorByRank.length - 1; i++) {
            if (tokenByRank(i) >= tokenByRank(i + 1)) {
                break;
            }
            _moveValRank(i, i + 1);
        }
    }

    function createValidator(
        uint256 commissionRate,
        uint256 commissionMaxChangeRate,
        uint256 commissionMaxRate,
        uint256 minselfDelegation,
        string memory name,
        string memory website,
        string memory contact,
        string memory identity
    ) public payable {
        require(
            validators[msg.sender].operatorAddress == address(0x0),
            "Validator Owner Exists"
        );
        require(
            commissionMaxRate <= onDec,
            "commission can not be more than 100%"
        );
        require(
            commissionRate <= commissionMaxRate,
            "commission rate can not be more than max rate"
        );
        require(
            commissionMaxChangeRate <= commissionMaxRate,
            "commission max change can not be more than max rate"
        );

        validators[msg.sender] = Validator({
            operatorAddress: msg.sender,
            rewards: 0,
            commissionRewards: 0,
            jailed: false,
            tokens: 0,
            commission: Commission({
                rate: commissionRate,
                maxRate: commissionMaxChangeRate,
                maxChangeRate: commissionMaxRate
            }),
            updateTime: block.timestamp,
            cumulativeRewardRatio: 0,
            cumulativeSlashRatio: 0,
            missedBlockCounter: 0,
            jailedUntil: 0,
            minselfDelegation: minselfDelegation,
            rank: validatorByRank.length,
            unboudingEntryCount: 0,
            description: Description({
                name: name,
                website: website,
                contact: contact,
                identity: identity
            })
        });

        validatorByRank.push(msg.sender);
        _delegate(msg.sender, msg.sender, msg.value);
    }

    function _delegate(address delAddr, address valAddr, uint256 amount)
        private
    {
        Validator storage val = validators[valAddr];
        Delegation storage del = delegations[valAddr][delAddr];

        // increment token amount
        val.tokens += amount;

        // update delegate starting info
        del.stake += amount;
        del.cumulativeSlashRatio = val.cumulativeSlashRatio;
        del.cumulativeRewardRatio = val.cumulativeRewardRatio;

        totalBonded += amount;

        if (!val.jailed) {
            sortRankByVotingPower(val.rank);
        }
    }

    function delegate(address valAddr) public payable {
        require(validators[valAddr].operatorAddress != address(0x0), "validator not found");
        // withdrawl reward before redelegate
        withdrawDelegationReward(valAddr);
        _delegate(msg.sender, valAddr, msg.value);
    }

    function getCurrentValidatorSet()
        public
        view
        returns (address[] memory, uint256[] memory)
    {
        uint256 maxValidators = params.maxValidators;
        if (maxValidators > validatorByRank.length) {
            maxValidators = validatorByRank.length;
        }

        address[] memory arrProposer = new address[](maxValidators);
        uint256[] memory arrProposerVotingPower = new uint256[](maxValidators);

        for (uint256 i = 0; i < maxValidators; i++) {
            arrProposer[i] = validatorByRank[i];
            arrProposerVotingPower[i] = validators[validatorByRank[i]]
                .tokens
                .div(powerReduction);
        }

        return (arrProposer, arrProposerVotingPower);
    }

    function finalizeCommit(
        address proposerAddr,
        address[] memory addresses,
        bool[] memory signed,
        uint256[] memory powers,
        uint256 feeCollected
    ) public onlyRoot {
        uint256 previousTotalPower = 0;
        uint256 previousPrecommitTotalPower = 0;

        for (uint256 i = 0; i < signed.length; i++) {
            previousTotalPower += powers[i];
            if (signed[i]) {
                previousPrecommitTotalPower += powers[i];
            }
        }

        // allocateTokens
        if (previousProposerAddr != address(0x0)) {
            allocateTokens(
                previousTotalPower,
                previousPrecommitTotalPower,
                addresses,
                powers,
                feeCollected
            );
            handleValidateSignatures(addresses, signed, powers);
        }
        previousProposerAddr = proposerAddr;
    }
    function allocateTokens(
        uint256 previousTotalPower,
        uint256 previousPrecommitTotalPower,
        address[] memory addresses,
        uint256[] memory powers,
        uint256 feeCollected
    ) internal {
        if (previousTotalPower == 0) return;

        // calculate fraction votes
        uint256 previousFractionVotes = previousPrecommitTotalPower.divTrun(
            previousTotalPower
        );

        // calculate previous proposer reward
        uint256 proposerMultiplier = params.baseProposerReward.add(
            params.bonusProposerReward.mulTrun(previousFractionVotes)
        );
        uint256 proposerReward = feeCollected.mulTrun(proposerMultiplier);
        allocateTokensToVal(previousProposerAddr, proposerReward);
        uint256 voteMultiplier = onDec;
        voteMultiplier = voteMultiplier.sub(proposerMultiplier);
        for (uint256 i = 0; i < addresses.length; i++) {
            uint256 powerFraction = powers[i].divTrun(previousTotalPower);
            uint256 reward = feeCollected.mulTrun(voteMultiplier).mulTrun(
                powerFraction
            );
            if (validators[addresses[i]].operatorAddress != address(0x0)) {
                allocateTokensToVal(addresses[i], reward);
            }
        }

    }

    function allocateTokensToVal(address valAddr, uint256 blockReward) private {
        Validator storage val = validators[valAddr];
        uint256 commission = blockReward.mulTrun(val.commission.rate);
        uint256 shared = blockReward.sub(commission);
        val.commissionRewards += commission;
        val.rewards += shared;
    }

    function handleValidateSignatures(
        address[] memory addresses,
        bool[] memory signed,
        uint256[] memory powers
    ) private {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (validators[addresses[i]].operatorAddress != address(0x0)) {
                handleValidateSignature(addresses[i], powers[i], signed[i]);
            }
        }
    }

    function handleValidateSignature(
        address valAddr,
        uint256 power,
        bool signed
    ) private {
        Validator storage val = validators[valAddr];
        if (signed && val.missedBlockCounter > 0) {
            val.missedBlockCounter -= 1;
        } else {
            val.missedBlockCounter += 1;
        }

        if (val.missedBlockCounter >= params.maxMissed && !val.jailed) {
            slash(valAddr, power, params.slashFractionDowntime);
        }

    }

    function slash(address valAddr, uint256 votingPower, uint256 slashFractor)
        private
    {
        Validator storage val = validators[valAddr];
        uint256 slashAmount = votingPower.mul(powerReduction).mulTrun(slashFractor);
        val.tokens -= slashAmount;
        val.cumulativeSlashRatio += slashFractor;

        // jail validator
        val.jailed = true;
        val.missedBlockCounter = 0;
        val.jailedUntil += block.timestamp.add(params.downtimeJailDuration);
        burn(slashAmount);

        sortRankByVotingPower(val.rank);

    }

    function burn(uint256 amount) private {
        totalSupply -= amount;
        totalBonded -= amount;
    }

    function transferTo(address payable recipient, uint256 amount)
        public
        payable
    {
        recipient.transfer(amount);
        //emit Refund(recipient, amount);
    }

    function _withdrawDelegationRewards(address delAddr, address valAddr)
        private
        returns (uint256)
    {
        Validator storage val = validators[valAddr];
        Delegation storage del = delegations[valAddr][delAddr];

        if (val.rewards > 0) {
            val.cumulativeRewardRatio += val.rewards.divTrun(val.tokens);
        }

        del.stake = calculateDelegationStakeAmount(
            del.stake,
            val.cumulativeSlashRatio,
            del.cumulativeSlashRatio
        );

        uint256 difference = val.cumulativeRewardRatio.sub(
            del.cumulativeRewardRatio
        );
        uint256 rewards = difference.mulTrun(del.stake);
        val.rewards = 0;
        del.cumulativeRewardRatio = val.cumulativeRewardRatio;
        del.cumulativeSlashRatio = val.cumulativeSlashRatio;
        return rewards;
    }

    function calculateDelegationStakeAmount(
        uint256 amount,
        uint256 valCumulativeSlashRatio,
        uint256 delCumulativeSlashRatio
    ) private pure returns (uint256) {
        if (valCumulativeSlashRatio == 0) return amount;
        uint256 different = valCumulativeSlashRatio.sub(
            delCumulativeSlashRatio
        );
        uint256 slashAmount = amount.mulTrun(different);
        if (slashAmount > amount) {
            return 0;
        }
        return amount - slashAmount;
    }
    function withdraw(address valAddr) public {
        Validator storage val = validators[valAddr];
        Delegation storage del = delegations[valAddr][msg.sender];
        uint256 balance = 0;
        for (uint256 i = 0; i < del.ubdEntries.length; i++) {
            UnbondingDelegationEntry memory entry = del.ubdEntries[i];
            if (entry.completionTime < block.timestamp) {
                del.ubdEntries[i] = del.ubdEntries[del.ubdEntries.length - 1];
                del.ubdEntries.pop();
                i--;
                balance += calculateDelegationStakeAmount(
                    entry.balance,
                    val.cumulativeSlashRatio,
                    entry.cumulativeSlashRatio
                );
                val.unboudingEntryCount--;
                totalBonded -= balance;
            }
        }
        if (del.stake == 0 && del.ubdEntries.length == 0) {
            delete delegations[valAddr][msg.sender];
        }
        if (val.tokens == 0 && val.unboudingEntryCount == 0) {
            delete validators[valAddr];
        }
        transferTo(msg.sender, balance);
    }

    function getUnboudingDelegation(address delAddr, address valAddr)
        public
        view
        returns (uint256, uint256)
    {
        Validator storage val = validators[valAddr];
        Delegation storage del = delegations[valAddr][delAddr];
        uint256 balances = 0;
        uint256 sumTotalBalance = 0;
        for (uint256 i = 0; i < del.ubdEntries.length; i++) {
            UnbondingDelegationEntry memory entry = del.ubdEntries[i];
            entry.balance = calculateDelegationStakeAmount(
                entry.balance,
                val.cumulativeSlashRatio,
                entry.cumulativeSlashRatio
            );
            sumTotalBalance += entry.balance;
            if (entry.completionTime < block.timestamp) {
                balances += entry.balance;
            }
        }
        return (balances, sumTotalBalance);
    }

    function getValidator(address valAddr)
        public
        view
        returns (uint256, bool, uint256)
    {
        Validator memory val = validators[valAddr];
        return (val.tokens, val.jailed, val.jailedUntil);
    }

    function getDelegationRewards(address delAddr, address valAddr)
        public
        view
        returns (uint256)
    {
        Validator storage val = validators[valAddr];
        Delegation storage del = delegations[valAddr][delAddr];

        uint256 cumulativeRewardRatio = val.cumulativeRewardRatio;
        cumulativeRewardRatio += val.rewards.divTrun(val.tokens);
        uint256 stake = calculateDelegationStakeAmount(
            del.stake,
            val.cumulativeSlashRatio,
            del.cumulativeSlashRatio
        );
        uint256 difference = cumulativeRewardRatio.sub(
            del.cumulativeRewardRatio
        );
        return stake.mulTrun(difference);
    }

    function withdrawDelegationReward(address valAddr)
        public
        returns (uint256)
    {
        uint256 rewards = _withdrawDelegationRewards(msg.sender, valAddr);
        transferTo(msg.sender, rewards);
        return rewards;
    }

    function withdrawValidatorCommissionReward() public returns (uint256) {
        Validator storage val = validators[msg.sender];
        transferTo(msg.sender, val.commissionRewards);
        val.commissionRewards = 0;
    }

    function getValidatorCommissionReward(address valAddr)
        public
        view
        returns (uint256)
    {
        return validators[valAddr].commissionRewards;
    }

    function getDelegationStake(address delAddr, address valAddr)
        public
        view
        returns (uint256)
    {
        Validator storage val = validators[valAddr];
        Delegation storage del = delegations[valAddr][delAddr];
        uint256 stake = calculateDelegationStakeAmount(
            del.stake,
            val.cumulativeSlashRatio,
            del.cumulativeSlashRatio
        );
        return stake;
    }

    function undelegate(address valAddr, uint256 amount) public {
        withdrawDelegationReward(valAddr);
        Validator storage val = validators[valAddr];
        Delegation storage del = delegations[valAddr][msg.sender];
        del.stake -= amount;
        if (
            msg.sender == valAddr &&
            !val.jailed &&
            del.stake < val.minselfDelegation
        ) {
            val.jailed = true;
        }
        val.tokens -= amount;
        val.unboudingEntryCount++;
        del.ubdEntries.push(
            UnbondingDelegationEntry({
                balance: amount,
                completionTime: block.timestamp + params.unboudingTime,
                cumulativeSlashRatio: val.cumulativeSlashRatio
            })
        );
        if (!val.jailed) {
            sortRankByVotingPower(val.rank);
        }
    }

    function updateValidator(
        uint256 commissionRate,
        uint256 minselfDelegation,
        string memory name,
        string memory website,
        string memory contact,
        string memory identity
    ) public {
        Validator storage val = validators[msg.sender];
        if (commissionRate > 0) {
            require(
                (block.timestamp - val.updateTime) > 86400,
                "commission rate can not be changed more than one in 24h"
            );
            require(
                commissionRate < val.commission.maxRate,
                "commission rate can not be more than the max rate"
            );
            require(
                commissionRate.sub(val.commission.rate) <
                    val.commission.maxChangeRate,
                "commision rate can not be more than the max change rate"
            );
        }
        if (minselfDelegation > 0) {
            require(
                minselfDelegation > val.minselfDelegation,
                "min self delegation recreased"
            );
            require(
                minselfDelegation < val.tokens,
                "min self delegation below minumum"
            );
            val.minselfDelegation = minselfDelegation;
        }

        if (commissionRate > 0) {
            val.commission.rate = commissionRate;
            val.updateTime = block.timestamp;
        }

        if (bytes(name).length > 0) {
            val.description.name = name;
        }
        if (bytes(website).length > 0) {
            val.description.website = website;
        }
        if (bytes(identity).length > 0) {
            val.description.identity = identity;
        }
        if (bytes(contact).length > 0) {
            val.description.contact = contact;
        }
    }

    function unjail() public {
        Validator storage val = validators[msg.sender];
        Delegation storage del = delegations[msg.sender][msg.sender];
        require(val.jailed, "validator not jailed");
        require(
            del.stake > val.minselfDelegation,
            "selt delegation too low to unjail"
        );
        require(val.jailedUntil < block.timestamp, "validator jailed");

        val.jailedUntil = 0;
        val.jailed = false;
        val.rank = validatorByRank.length;
        validatorByRank.push(msg.sender);
        sortRankByVotingPower(val.rank);
    }

    function doubleSign(address valAddr, uint256 votingPower) public onlyRoot {
        Validator storage val = validators[valAddr];
        if (val.operatorAddress == address(0x0) || val.jailed) {
            return;
        }
        slash(valAddr, votingPower, params.slashFractionDoubleSign);
    }


    function nextInflationRate() {
        uint256 bondedRatio = totalBounded.divTrun(totalSupply);
        uint256 inflationChangeRatePerYear = 0;
        uint256 inflationRateChange = 0;
        if (bondedRatio.divTrun(params.goalBonded) > onDec) {
            inflationChangeRatePerYear =  bondedRatio.divTrun(params.goalBonded).sub(onDec)
                .mul(params.inflationRateChange);
            inflationRateChange = inflationRateChange.div(params.blocksPerYear);
            if (inflationRateChange < inflation) {
                inflation = inflation.sub(inflationRateChange);
            } else {
                inflation = 0;
            }
        } else {
            inflationChangeRatePerYear =  onDec.sub(bondedRatio.divTrun(params.goalBonded))
                .mul(params.inflationRateChange);
            inflationRateChange = inflationRateChange.div(params.blocksPerYear);
            inflation = inflation.add(inflationRateChange);
        }

        
        if (in > params.inflationMax) {
            inflation = params.inflationMax;
        }
        if (in < params.inflationMin) {
            inflation = params.inflationMin;
        }
    }

    function nextAnnualProvisions() {
        annualProvision = inflation.mulTrun(totalSupply); 
    }

    function getBlockProvision() public returns(uint256) {
        return annualProvision.div(params.blocksPerYear);
    }
    
}



