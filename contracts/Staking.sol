pragma solidity >=0.4.21 <0.7.0;
import {SafeMath} from "./Safemath.sol";

contract Staking {
    enum Status {Unbonded, Unbonding, Bonded}
    using SafeMath for uint256;
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
        uint256 slashFractionDowntimeRatio;
        uint256 minselfDelegation;
    }
    struct Delegation {
        uint256 height;
        uint256 stake;
        uint256 cumulativeRewardRatio;
        uint256 slashFractionDowntimeRatio;
    }

    struct Params {
        uint256 baseProposerReward;
        uint256 bonusProposerReward;
        uint256 maxValidators;
        uint256 maxMissed;
        uint256 downtimeJailDuration;
        uint256 slashFractionDowntime;
    }

    address previousProposerAddr;
    mapping(address => Validator) validators;
    mapping(address => mapping(address => Delegation)) delegations;

    address[] validatorSets;

    Params params;

    modifier onlyOwner() {
        require(msg.sender == address(this), "sender is not owner");
        _;
    }

    constructor(
        uint256 maxValidators,
        uint256 maxMissed,
        uint256 downtimeJailDuration,
        uint256 baseProposerReward,
        uint256 bonusProposerReward,
        uint256 slashFractionDowntime
    ) public {
        params = Params({
            maxValidators: maxValidators,
            maxMissed: maxMissed,
            downtimeJailDuration: downtimeJailDuration,
            baseProposerReward: baseProposerReward,
            bonusProposerReward: bonusProposerReward,
            slashFractionDowntime: slashFractionDowntime
        });
    }

    function setParams(
        uint256 maxValidators,
        uint256 maxMissed,
        uint256 downtimeJailDuration,
        uint256 baseProposerReward,
        uint256 bonusProposerReward,
        uint256 slashFractionDowntime
    ) public {
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
    }

    function createValidator(uint256 commissionRate, uint256 minselfDelegation)
        public
        payable
    {
        require(validators[msg.sender].operatorAddress == address(0x0), "Validator Owner Exists");

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
            missedBlockCounter: 0,
            jailedUntil: 0,
            slashFractionDowntimeRatio: 0,
            minselfDelegation: minselfDelegation
        });


        validatorSets.push(msg.sender);

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
        del.slashFractionDowntimeRatio = val.slashFractionDowntimeRatio;
        del.cumulativeRewardRatio = val.cumulativeRewardRatio;
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
        address[] memory addresses = new address[](validatorSets.length);
        uint256[] memory votingPowers = new uint256[](validatorSets.length);

        for (uint256 i = 0; i < validatorSets.length; i++) {
            addresses[i] = validators[validatorSets[i]].operatorAddress;
            votingPowers[i] = validators[validatorSets[i]].tokens;
        }

        return (addresses, votingPowers);
    }

    function finalizeCommit(
        address proposerAddr,
        address[] memory addresses,
        bool[] memory signed,
        uint256[] memory powers
    ) public {
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
                powers
            );
            handleValidateSignatures(addresses, signed, powers);
        }
        previousProposerAddr = proposerAddr;
    }


    function allocateTokens(
        uint256 previousTotalPower,
        uint256 previousPrecommitTotalPower,
        address[] memory addresses,
        uint256[] memory powers
    ) internal {
        if (previousTotalPower == 0) return;
        uint256 feeCollected = 1 * 10**18;

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
            allocateTokensToVal(addresses[i], reward);
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
        for (uint256 i = 0; i < signed.length; i++) {
            handleValidateSignature(addresses[i], powers[i], signed[i]);
        }
    }

    function handleValidateSignature(
        address valAddr,
        uint256 power,
        bool signed
    ) internal {
        Validator storage val = validators[valAddr];
        if (signed) {
            val.missedBlockCounter -= 1;
        } else {
            val.missedBlockCounter += 1;
        }

        if (val.missedBlockCounter >= params.maxMissed) {
            val.jailed = true;
            val.missedBlockCounter = 0;
            val.jailedUntil += block.timestamp.add(params.downtimeJailDuration);
            slash(valAddr, power);
        }

    }

    function slash(address valAddr, uint256 power) private {
        Validator storage val = validators[valAddr];
        uint256 slashAmount = power.mulTrun(params.slashFractionDowntime);
        val.tokens -= slashAmount;
        val.slashFractionDowntimeRatio += params.slashFractionDowntime;
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

        if (val.slashFractionDowntimeRatio > 0) {
            del.stake = del.stake.mulTrun(
                val.slashFractionDowntimeRatio.sub(del.slashFractionDowntimeRatio)
            );
        }
        uint256 difference = val.cumulativeRewardRatio.sub(
            del.cumulativeRewardRatio
        );
        uint256 rewards = difference.mulTrun(del.stake);
        val.rewards = 0;
        del.cumulativeRewardRatio = val.cumulativeRewardRatio;
        del.slashFractionDowntimeRatio = val.slashFractionDowntimeRatio;
        return rewards;
    }

    function getValidator(address valAddr) public view returns (uint256, bool) {
        Validator memory val = validators[valAddr];
        return (val.tokens, val.jailed);
    }


    function getDelegationRewards(address delAddr, address valAddr) public view returns(uint256) {
        Validator storage val = validators[valAddr];
        Delegation storage del = delegations[valAddr][delAddr];

        uint256 stake = del.stake;
        uint256 cumulativeRewardRatio = val.cumulativeRewardRatio + val.rewards.divTrun(val.tokens);

        if (val.slashFractionDowntimeRatio > 0) {
            stake = del.stake.mulTrun(
                val.slashFractionDowntimeRatio.sub(del.slashFractionDowntimeRatio)
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

    function getValidatorCommissionReward(address valAddr) public view returns(uint256) {
        return validators[valAddr].commissionRewards;
    }

    function getDelegationStake(address delAddr, address valAddr) public view returns(uint256) {
        return delegations[valAddr][delAddr].stake;
    }

    function undelegate(address valAddr) public returns (uint256) {
        withdrawDelegationReward(valAddr);

        Validator storage val = validators[msg.sender];
        Delegation storage del = delegations[valAddr][msg.sender];

        val.tokens -= del.stake;
        del.stake = 0;

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

    }
}
