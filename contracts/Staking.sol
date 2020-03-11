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
    address previousProposerAddr;
    uint256 baseProposerReward;
    uint256 bonusProposerReward;
    uint256 maxValidator;
    uint256 maxMissed;
    uint256 downtimeJailDuration;
    uint256 slashFractionDowntime;

    // A dynamically-sized array of `Validator` structs.
    Validator[] validators;

    mapping(address => uint256) validateByAddress;
    mapping(address => mapping(address => Delegation)) delegations;

    modifier onlyValidatorOwner(address valAddr) {
        require(
            validators[validateByAddress[valAddr]].operatorAddress ==
                msg.sender,
            "sender not validator owner"
        );
        _;
    }

    constructor(
        uint256 maxVal,
        uint256 _maxMissed,
        uint256 _downtimeJailDuration
    ) public {
        maxValidator = maxVal;
        maxMissed = _maxMissed;
        downtimeJailDuration = _downtimeJailDuration;
    }

    function createValidator(uint256 commissionRate, uint256 minselfDelegation)
        public
        payable
    {
        require(validateByAddress[msg.sender] == 0, "Validator Owner Exists");

        validators.push(
            Validator({
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
            })
        );

        validateByAddress[msg.sender] = validators.length;

        _delegate(msg.sender, msg.sender, msg.value);
    }

    function _delegate(address delAddr, address valAddr, uint256 amount)
        private
    {
        Validator storage val = validators[validateByAddress[valAddr] - 1];
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
        address[] memory addresses = new address[](validators.length);
        uint256[] memory votingPowers = new uint256[](validators.length);

        for (uint256 i = 0; i < validators.length; i++) {
            addresses[i] = validators[i].operatorAddress;
            votingPowers[i] = validators[i].tokens;
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
            //handleValidateSignatures(addresses, signed, powers);
        }
        previousProposerAddr = proposerAddr;
    }

    function allocateTokens(
        uint256 previousTotalPower,
        uint256 previousPrecommitTotalPower,
        address[] memory addresses,
        uint256[] memory powers
    ) private {
        if (previousTotalPower == 0) return;
        uint256 feeCollected = 10;

        // calculate fraction votes
        uint256 previousFractionVotes = previousPrecommitTotalPower.divTrun(
            previousTotalPower
        );

        // calculate previous proposer reward
        uint256 proposerMultiplier = baseProposerReward.add(
            bonusProposerReward.mulTrun(previousFractionVotes)
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

    function allocateTokensToVal(address valAddr, uint256 reward) internal {
        Validator memory val = validators[validateByAddress[valAddr] - 1];
        uint256 commission = reward.mulTrun(val.commissionRate);
        uint256 shared = reward.sub(commission);
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
        Validator storage val = validators[validateByAddress[valAddr]];
        if (signed) {
            val.missedBlockCounter -= 1;
        } else {
            val.missedBlockCounter += 1;
        }

        if (val.missedBlockCounter >= maxMissed) {
            val.jailed = true;
            val.missedBlockCounter = 0;
            val.jailedUntil += block.timestamp.add(downtimeJailDuration);
            slash(valAddr, power);
        }

    }

    function slash(address valAddr, uint256 power) private {
        Validator storage val = validators[validateByAddress[valAddr]];
        uint256 slashAmount = power.mulTrun(slashFractionDowntime);
        val.tokens -= slashAmount;
        val.slashFractionDowntimeRatio += slashFractionDowntime;
    }

    function transferTo(address payable recipient, uint256 amount)
        public
        payable
    {
        recipient.transfer(amount);
        //emit Refund(recipient, amount);
    }

    function withdrawDelegationRewards(address delAddr, address valAddr)
        private
        returns (uint256)
    {
        Validator storage val = validators[validateByAddress[valAddr] - 1];
        Delegation storage del = delegations[valAddr][delAddr];

        val.cumulativeRewardRatio += val.rewards.divTrun(val.tokens);
        del.stake = del.stake.mulTrun(
            val.slashFractionDowntimeRatio.sub(del.slashFractionDowntimeRatio)
        );

        uint256 difference = val.cumulativeRewardRatio.sub(
            del.cumulativeRewardRatio
        );
        uint256 rewards = del.stake.mulTrun(difference);
        del.cumulativeRewardRatio = val.cumulativeRewardRatio;
        del.slashFractionDowntimeRatio = val.slashFractionDowntimeRatio;
        val.rewards = 0;
        return rewards;
    }

    function withdrawDelegationReward(address valAddr)
        public
        returns (uint256)
    {
        uint256 rewards = withdrawDelegationRewards(msg.sender, valAddr);
        transferTo(msg.sender, rewards);
        return rewards;
    }

    function withdrawValidatorCommissionReward() public returns (uint256) {
        Validator storage val = validators[validateByAddress[msg.sender]];
        transferTo(msg.sender, val.commissionRewards);
        val.commissionRewards = 0;
    }

    function undelegate(address valAddr) public returns (uint256) {
        withdrawDelegationReward(valAddr);

        Validator storage val = validators[validateByAddress[valAddr]];
        Delegation storage del = delegations[valAddr][msg.sender];

        val.tokens -= del.stake;
        del.stake = 0;

        return del.stake;
    }

    function updateValidator(uint256 commissionRate, uint256 minselfDelegation)
        public
    {
        Validator storage val = validators[validateByAddress[msg.sender]];
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
        Validator storage val = validators[validateByAddress[msg.sender] - 1];
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
