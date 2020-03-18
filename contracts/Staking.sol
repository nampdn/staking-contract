pragma solidity >=0.4.21 <0.7.0;
import {SafeMath} from "./Safemath.sol";

contract Staking {
    enum Status {Unbonded, Unbonding, Bonded}
    using SafeMath for uint256;
    uint256 powerReduction = 1 * 10 ** 6;
    struct Validator {
        address operatorAddress;
        uint256 tokens;
        bool jailed;
        uint256 commissionRate;
        Status status;
        uint256 rewards;
        uint256 commissionRewards;
        uint256 updateTime;
        uint256 cumulativeRewardRatio;
        uint256 missedBlockCounter;
        uint256 jailedUntil;
        uint256 cumulativeSlashRatio;
        uint256 minselfDelegation;
        uint256 rank;
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
    }

    address previousProposerAddr;
    mapping(address => Validator) validators;
    mapping(address => mapping(address => Delegation)) delegations;
    address[] public validatorByRank;

    Params params;

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

    function sortRankByVotingPower(uint256 idx) private {
        _sortRankByVotingPower(0, validatorByRank.length - 1);
        cleanValidatorByRankArr();
    }

    function cleanValidatorByRankArr() private {
        for (uint256 i = validatorByRank.length - 1; i <= 0; i--) {
            if (tokenByRank(i) > 0) break;
            validatorByRank.pop();
        }
    }

    function _sortRankByVotingPower(uint256 left, uint256 right) private {
        uint256 i = left;
        uint256 j = right;
        if (i == j) return;
        uint256 pivot = tokenByRank(left + (right - left) / 2);
        while (i <= j) {
            while (tokenByRank(i) > pivot) i++;
            while (pivot > tokenByRank(j)) j--;
            if (i <= j) {
                address tmp = validatorByRank[i];
                validatorByRank[i] = validatorByRank[j];
                validatorByRank[j] = tmp;
                i++;
                j--;
            }
        }
        if (left < j) _sortRankByVotingPower(left, j);

        if (i < right) _sortRankByVotingPower(i, right);

    }

    function createValidator(uint256 commissionRate, uint256 minselfDelegation)
        public
        payable
    {
        require(
            validators[msg.sender].operatorAddress == address(0x0),
            "Validator Owner Exists"
        );
        validators[msg.sender] = Validator({
            operatorAddress: msg.sender,
            rewards: 0,
            commissionRewards: 0,
            jailed: false,
            tokens: 0,
            status: Status.Unbonded,
            commissionRate: commissionRate,
            updateTime: block.timestamp,
            cumulativeRewardRatio: 0,
            cumulativeSlashRatio: 0,
            missedBlockCounter: 0,
            jailedUntil: 0,
            minselfDelegation: minselfDelegation,
            rank: validatorByRank.length
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
        sortRankByVotingPower(val.rank);
    }

    function delegate(address valAddr) public payable {
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
            arrProposerVotingPower[i] = validators[validatorByRank[i]].tokens.div(powerReduction);
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

        uint256 voteMultiplier = 1 * 10**18;
        voteMultiplier = voteMultiplier.sub(proposerMultiplier);
        for (uint256 i = 0; i < addresses.length; i++) {
            uint256 powerFraction = powers[i].divTrun(previousTotalPower);
            uint256 reward = feeCollected.mulTrun(voteMultiplier).divTrun(
                powerFraction
            );

            if (validators[addresses[i]].operatorAddress != address(0x0)) {
                allocateTokensToVal(addresses[i], reward);
            }
        }

    }

    function allocateTokensToVal(address valAddr, uint256 blockReward) private {
        Validator storage val = validators[valAddr];
        uint256 commission = blockReward.mulTrun(val.commissionRate);
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
        uint256 slashAmount = votingPower.mulTrun(slashFractor);
        val.tokens -= slashAmount;
        val.cumulativeSlashRatio += slashFractor;

        // jail validator
        val.jailed = true;
        val.missedBlockCounter = 0;
        val.jailedUntil += block.timestamp.add(params.downtimeJailDuration);

        sortRankByVotingPower(val.rank);

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

        if (val.rewards == 0) {
            return 0;
        }

        val.cumulativeRewardRatio += val.rewards.divTrun(val.tokens);

        if (val.cumulativeSlashRatio > 0) {
            del.stake = del.stake.mulTrun(
                val.cumulativeSlashRatio.sub(del.cumulativeSlashRatio)
            );
        }
        uint256 difference = val.cumulativeRewardRatio.sub(
            del.cumulativeRewardRatio
        );
        uint256 rewards = difference.mulTrun(del.stake);
        val.rewards = 0;
        del.cumulativeRewardRatio = val.cumulativeRewardRatio;
        del.cumulativeSlashRatio = val.cumulativeSlashRatio;
        return rewards;
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
                balance += entry.balance;
                if (val.cumulativeSlashRatio > 0) {
                    uint256 slashAmount = balance.mulTrun(
                            val.cumulativeSlashRatio.sub(
                                entry.cumulativeSlashRatio
                            )
                        );
                    if (slashAmount > balance) {
                        balance = 0;
                    } else {
                        balance -= slashAmount;
                    }

                }
            }
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
            if (val.cumulativeSlashRatio > 0) {
                uint256 slashAmount = entry.balance.mulTrun(
                    val.cumulativeSlashRatio.sub(entry.cumulativeSlashRatio)
                );

                if (slashAmount > entry.balance) {
                    entry.balance = 0;
                } else {
                    entry.balance -= slashAmount;
                }
            }

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

        uint256 stake = del.stake;
        uint256 cumulativeRewardRatio = val.cumulativeRewardRatio;
        cumulativeRewardRatio += val.rewards.divTrun(val.tokens);

        if (val.cumulativeSlashRatio > 0) {
            stake = stake.sub(
                del.stake.mulTrun(
                    val.cumulativeSlashRatio.sub(del.cumulativeSlashRatio)
                )
            );
        }
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
        uint256 stake = del.stake;
        if (val.cumulativeSlashRatio > 0) {
            stake = stake.sub(
                stake.mulTrun(
                    val.cumulativeSlashRatio.sub(del.cumulativeSlashRatio)
                )
            );
        }
        return stake;
    }

     event Undelegate(uint256 cumulativeSlashRatio);

    function undelegate(address valAddr, uint256 amount)
        public
        returns (uint256)
    {
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

        val.tokens -= del.stake;
        del.ubdEntries.push(
            UnbondingDelegationEntry({
                balance: amount,
                completionTime: block.timestamp + params.unboudingTime,
                cumulativeSlashRatio: val.cumulativeSlashRatio
            })
        );
        emit Undelegate(val.cumulativeSlashRatio);
        sortRankByVotingPower(val.rank);
        return del.stake;
    }

    function updateValidator(uint256 commissionRate, uint256 minselfDelegation)
        public
    {
        Validator storage val = validators[msg.sender];
        if (commissionRate > 0) {
            val.commissionRate = commissionRate;
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
        if (val.operatorAddress == address(0x0)) {
            return;
        }
        slash(valAddr, votingPower, params.slashFractionDoubleSign);
    }
}
