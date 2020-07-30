const Staking = artifacts.require("Staking");
const utils = require("./utils");


async function assertRevert(promise, includeStr = "") {
    return promise.then(() => {
        throw null;
    }).catch(e => {
        assert.isNotNull(e);
        if (includeStr != "" && e != null) {
            assert.include(e.message, includeStr);
        }
    });
}

async function setParams(owner, isOk) {
    const baseProposerReward = web3.utils.toWei("0.1", "ether") // 10%
    const bonusProposerReward = web3.utils.toWei("0.01", "ether") // 1%
    const slashFractionDowntime = web3.utils.toWei("0.1", "ether") // 10%
    const slashFractionDoubleSign = web3.utils.toWei("0.5", "ether") // 50%
    const unBondingTime = 1;
    const signedBlockWindow= 2;
    const minSignedBlockPerWindow = web3.utils.toWei("0.5", "ether")
    let instance = await Staking.deployed(); 
    const promise =  instance.setParams(100, 600, baseProposerReward, bonusProposerReward, 
        slashFractionDowntime, unBondingTime, slashFractionDoubleSign, signedBlockWindow, minSignedBlockPerWindow, {from: owner})
    if (isOk) {
        await promise;
    } else {
        await assertRevert(promise, "Ownable: caller is not the owner");
    }
}

contract("Staking", async (accounts) => {
    const powerReduction = Math.pow(10, 6);
    async function finalizeCommit(notSigned) {
        notSigned = notSigned  || [];
        let instance = await Staking.deployed();
        const validatorSet = await getCurrentValidatorSet();
        await instance.mint();
        const blockProvision = await  instance.getBlockProvision.call();
        await instance.deposit({from: accounts[0], value: blockProvision.toString()})
        await instance.setPreviousProposer(accounts[0]);
        let signed = validatorSet[0].map(addr => notSigned.indexOf(addr) === -1);
        await instance.finalizeCommit(validatorSet[0], validatorSet[1], signed)
    }

    async function getCurrentValidatorSet() {
        const instance = await Staking.deployed();
        await instance.applyAndReturnValidatorSets({from: accounts[0]});
        return instance.getValidatorSets.call();
    }

    async function mint(num) {
        const instance = await Staking.deployed();
        for (var i =0; i < num; i ++) {
            await instance.mint();
        }
    }

    it ("should transfer ownership", async() => {
        let instance = await Staking.deployed();
        await instance.transferOwnership(accounts[0], {from: accounts[0]});
    });

    it ("should not transfer ownership", async () => {
        let instance = await Staking.deployed();
        await assertRevert(instance.transferOwnership(accounts[0], {from: accounts[1]}), "Ownable: caller is not the owner");
    });

    it ("should set previous proposer", async () => {
        let instance = await Staking.deployed();
        await instance.setPreviousProposer(accounts[0])
    });

    it ("should not set previous proposer", async () => {
        let instance = await Staking.deployed();
        await assertRevert(instance.setPreviousProposer(accounts[0], { from: accounts[1]}), "Ownable: caller is not the owner");
    });

    it ("should set params", async() => {
        await setParams(accounts[0], true);
    });

    it ("should not set params", async() => {
        await setParams(accounts[1]);
    });

    it ("should finalize", async () => {
        const instance = await Staking.deployed();
        await instance.finalizeCommit([accounts[0], accounts[1]], [1,2], [true, true], {from: accounts[0]})
    });

    it ("should not finalize", async () => {
        const instance = await Staking.deployed();
        await assertRevert(instance.finalizeCommit([accounts[0], accounts[1]], [1, 2], [true, true], {from: accounts[1]}), "Ownable: caller is not the owner");
    });


    it ("should set total bonded", async () => {
        const instance = await Staking.deployed();
        await instance.setTotalBonded(web3.utils.toWei("5000000000", "ether"), {from: accounts[0]});
    });

    it ("should not set total bonded", async () => {
        const instance = await Staking.deployed();
        await assertRevert(instance.setTotalBonded(1, {from: accounts[2]}), "Ownable: caller is not the owner");
    })

    it ("should set total supply", async () => {
        const instance = await Staking.deployed();
        await instance.setTotalSupply(1, {from: accounts[0]});

        const totalSupply = await instance.getTotalSupply();
        assert.equal(totalSupply.words[0].toString(), "1");
    });

    it ("should not set total supply", async () => {
        const instance = await Staking.deployed();
        await assertRevert(instance.setTotalSupply(1, {from: accounts[2]}), "Ownable: caller is not the owner");
    });

    it ("should set inflation", async () => {
        const instance = await Staking.deployed();
        await instance.setInflation(100, {from: accounts[0]});

        let inflation = await instance.inflation();
        assert.equal(inflation.words[0].toString(), "100");
    });

    it ("should not set inflation", async () => {
        const instance = await Staking.deployed();
        await assertRevert(instance.setInflation(1, {from: accounts[2]}), "Ownable: caller is not the owner");
    });

    it ("should not set mint params", async () => {
        const instance = await Staking.deployed();
        await assertRevert(instance.setMintParams(0,0,5,0,0, {from: accounts[2]}), "Ownable: caller is not the owner");
    });

    it ("should set mint params", async () => {
        const inflationRateChange = web3.utils.toWei("0.013", "ether");
        const goalBonded = web3.utils.toWei("0.067", "ether");
        const blocksPerYear = 6311520;
        const inflationMax = web3.utils.toWei("0.02", "ether");
        const inflationMin = web3.utils.toWei("0.007", "ether");
        const instance = await Staking.deployed();
        await instance.setMintParams(inflationRateChange,goalBonded,blocksPerYear,inflationMax,inflationMin);
    });

    it ("should set annual provision", async () => {
        const instance = await Staking.deployed();
        await instance.setAnnualProvision(10, {from: accounts[0]});

        let annualProvision = await instance.annualProvision();
        assert.equal(annualProvision.words[0].toString(), "10");
    });

    it ("should not set annual provision", async () => {
        const instance = await Staking.deployed();
        await assertRevert( instance.setAnnualProvision(0, {from: accounts[2]}), "Ownable: caller is not the owner");
    });
    
    it("should create validator", async () => {
        const instance = await Staking.deployed();
        const maxRate = web3.utils.toWei("0.05", "ether");
        const maxChangeRate = web3.utils.toWei("0.01", "ether");
        const minSelfDelegation = web3.utils.toWei("0.05", "ether");

        const bond = web3.utils.toWei("1", "ether");
        await instance.createValidator(0, maxRate, maxChangeRate ,minSelfDelegation, {from: accounts[0], value: bond});
        let validatorSet = await getCurrentValidatorSet();
        assert.equal(validatorSet[0][0], accounts[0]);
        assert.equal(validatorSet[1][0].toString(), bond/powerReduction);

        // check get delegation
        const delegation = await instance.getDelegation.call(accounts[0], accounts[0]);
        assert.equal(delegation.toString(), web3.utils.toWei("1", "ether"));

        // check delegation not found
        await assertRevert(instance.getDelegation.call(accounts[0], accounts[1]), "delegation not found");

        // check validator
        const validator = await instance.getValidator(accounts[0]);
        assert.equal(validator[0].toString(), bond);
        assert.equal(validator[1].toString(), web3.utils.toWei("1", "ether"));
        assert.equal(validator[2], false);

        const validators = await instance.getValidators.call();
        assert.equal(validators[0][0], accounts[0]);
        assert.equal(validators[1][0].toString(), bond);

        const stake = await instance.getAllDelegatorStake.call(accounts[0]);
        assert.equal(stake.toString(), bond);
    });

    it ("should not create validator", async() => {
        const instance = await Staking.deployed();
        const bond = web3.utils.toWei("1", "ether")
        const testCases = [
            {
                rate: 0,
                maxRate: 0,
                maxChangeRate: 0,
                minSelfDelegation: 0,
                from: accounts[0],
                value: bond,
                message: "validator already exist"
            }, 
            {
                rate: 0,
                maxRate: web3.utils.toWei("1.1", "ether"),
                maxChangeRate: 0,
                minSelfDelegation: 0,
                from: accounts[5],
                value: 0,
                message: "invalid delegation amount"
            },
            {
                rate: 0,
                maxRate: web3.utils.toWei("1.1", "ether"),
                maxChangeRate: 0,
                minSelfDelegation: 0,
                from: accounts[5],
                value: bond,
                message: "commission max rate cannot be more than 100%"
            },
            {
                rate: web3.utils.toWei("1", "ether"),
                maxRate: web3.utils.toWei("0.9", "ether"),
                maxChangeRate: 0,
                minSelfDelegation: 0,
                from: accounts[5],
                value: bond,
                message: "commission rate cannot be more than the max rate"
            },
            {
                rate: 0,
                maxRate: web3.utils.toWei("0.9", "ether"),
                maxChangeRate: web3.utils.toWei("1", "ether"),
                minSelfDelegation: 0,
                from: accounts[5],
                value: bond,
                message: "commission max change rate can not be more than the max rate"
            },
            {
                rate: 0,
                maxRate: 0,
                maxChangeRate: 0,
                minSelfDelegation:  web3.utils.toWei("2", "ether"),
                from: accounts[5],
                value: bond,
                message: "self delegation below minimum"
            }
        ];

        for(var testCase of testCases) {
            await assertRevert(instance.createValidator(testCase.rate, testCase.maxRate, testCase.maxChangeRate ,
                testCase.minSelfDelegation, {from: testCase.from, value: testCase.value}), testCase.message);
        }
    });

    it ("should not update validator", async () => {
        const instance = await Staking.deployed();
        await assertRevert(instance.updateValidator(1, 0, {from: accounts[5]}), "validator not found");

        let minSelfDelegation = web3.utils.toWei("0.04", "ether");
        await assertRevert(instance.updateValidator(0, minSelfDelegation, {from: accounts[0]}), "minimum self delegation cannot be decrease");

        minSelfDelegation = web3.utils.toWei("11", "ether");
        await assertRevert(instance.updateValidator(0, minSelfDelegation, {from: accounts[0]}), "self delegation below minimum");

        let commissionRate = web3.utils.toWei("0.011", "ether");
        await assertRevert(instance.updateValidator(commissionRate, 0, {from: accounts[0]}), "commission cannot be changed more than one in 24h");
        await utils.advanceTime(86401);

        commissionRate = web3.utils.toWei("0.03", "ether");
        await assertRevert(instance.updateValidator(commissionRate, 0, {from: accounts[0]}), "commission cannot be changed more than max change rate");
    });

    it ("should update validator", async () => {
        const instance = await Staking.deployed();

        let minSelfDelegation = web3.utils.toWei("0.051", "ether");
        let commissionRate = web3.utils.toWei("0.001", "ether");
        await instance.updateValidator(commissionRate, minSelfDelegation, {from: accounts[0]});
    });

    it ("should not delegate", async () => {
        const instance = await Staking.deployed();
        const bond1to0 = web3.utils.toWei("1", "ether");
        
        // validator not found
        await assertRevert(instance.delegate(accounts[5], {from: accounts[1], value: bond1to0}), "validator not found");

        // invalid delegation amount
        await assertRevert(instance.delegate(accounts[0], {from: accounts[1], value: 0}), "invalid delegation amount");

    });

    it ("should delegate", async() => {
        const instance = await Staking.deployed();
        const bond1to0 = web3.utils.toWei("0.5", "ether");
        await instance.delegate(accounts[0], {from: accounts[1], value: bond1to0});
        await instance.delegate(accounts[0], {from: accounts[2], value: bond1to0});

        const delegations = await instance.getDelegationsByValidator.call(accounts[0]);
        assert.equal(delegations[0][1], accounts[1]);
        assert.equal(delegations[0][2], accounts[2]);
        assert.equal(delegations[1][1].toString(), bond1to0.toString());
        assert.equal(delegations[1][2].toString(), bond1to0.toString());

        const validators1 = await instance.getValidatorsByDelegator.call(accounts[1]);
        const validators2 = await instance.getValidatorsByDelegator.call(accounts[2]);
        assert.equal(validators1[0], accounts[0]);
        assert.equal(validators2[0], accounts[0]);

        // check delegation
        const delegation = await instance.getDelegation.call(accounts[0], accounts[1]);
        assert.equal(delegation.toString(), web3.utils.toWei("0.5", "ether"))

        // check delegation not found
        await assertRevert( instance.getDelegation.call(accounts[0], accounts[4]), "delegation not found");
    });

    it ("should not undelegate", async () => {
        const instance = await Staking.deployed();
        const amount = web3.utils.toWei("1.5", "ether");

        // delegation not found
        await assertRevert(instance.undelegate(accounts[0], amount, {from: accounts[5]} ), "delegation not found")

        // invalid undelegate amount
        await assertRevert(instance.undelegate(accounts[0], amount, {from: accounts[1]}), "not enough delegation shares");
    });

    it ("should undelegate", async() => {
        const instance = await Staking.deployed();
        const amount1 = web3.utils.toWei("0.4", "ether");
        const amount2 = web3.utils.toWei("0.3", "ether");

        await instance.undelegate(accounts[0], amount1, {from: accounts[1]});
        await instance.undelegate(accounts[0], amount2, {from: accounts[2]});

        // check delegation
        const delegation1 = await instance.getDelegation.call(accounts[0], accounts[1]);
        assert.equal(delegation1.toString(), web3.utils.toWei("0.1", "ether"))

        const delegation2 = await instance.getDelegation.call(accounts[0], accounts[2]);
        assert.equal(delegation2.toString(), web3.utils.toWei("0.2", "ether"))

        const udbEntries1 = await instance.getUBDEntries.call(accounts[0], accounts[1]);
        const udbEntries2 = await instance.getUBDEntries.call(accounts[0], accounts[2]);

        assert.equal(udbEntries1[0][0].toString(), amount1);
        assert.equal(udbEntries2[0][0].toString(), amount2);
    });

    it ("should remove delegation", async() => {
        const instance = await Staking.deployed();
        const amount1 = web3.utils.toWei("0.1", "ether");
        const amount2 = web3.utils.toWei("0.2", "ether");

        await instance.undelegate(accounts[0], amount1, {from: accounts[1]});
        await instance.undelegate(accounts[0], amount2, {from: accounts[2]});

        await utils.advanceTime(2001);
        await instance.withdraw(accounts[0], {from: accounts[1]});
        await instance.withdraw(accounts[0], {from: accounts[2]});

        await assertRevert(instance.getDelegation.call(accounts[0], accounts[1]), "delegation not found");
        await assertRevert(instance.getDelegation.call(accounts[0], accounts[2]), "delegation not found");
    });
    
    it ("should not withdraw", async () => {
        const instance = await Staking.deployed();
        const amount = web3.utils.toWei("1", "ether");
        await instance.undelegate(accounts[0], amount, {from: accounts[0]});
        await assertRevert(instance.withdraw(accounts[0], {from: accounts[0]}), "no unbonding amount to withdraw");
    });

    it ("should withdraw", async () => {
        const instance = await Staking.deployed();
        await utils.advanceTime(2000);
        await instance.withdraw(accounts[0], {from: accounts[0]});

        // check delegation not found
        await assertRevert(instance.withdraw(accounts[0], {from: accounts[0]}), "delegation not found");
    });

    it ("should remove validator", async() => {
        const instance = await Staking.deployed();
        await assertRevert(instance.getValidator.call(accounts[0]), "validator not found");
        const validatorSets = await getCurrentValidatorSet();
        assert.equal(validatorSets[0].length, 0);
    });

    it ("calculate delegation rewards", async () => {
        const instance = await Staking.deployed();

        const bond0to0 = web3.utils.toWei("1", "ether");
        const bond1to0 = web3.utils.toWei("1", "ether");
        const bond2to0 = web3.utils.toWei("1", "ether");

        const bond1to1 = web3.utils.toWei("1", "ether");
        const bond2to2 = web3.utils.toWei("1", "ether");


        await instance.createValidator(0, 0,0, 0, {from: accounts[0], value: bond0to0});
        await instance.delegate(accounts[0], {from: accounts[1], value: bond1to0});
        await instance.delegate(accounts[0], {from: accounts[2], value: bond2to0});
        await instance.createValidator(0, 0,0, 0, {from: accounts[1], value: bond1to1});
        await instance.createValidator(0, 0,0, 0, {from: accounts[2], value: bond2to2});


        await finalizeCommit([]);

        // proposer base reward: 55,454153675 *  (10+ 1)% = 6,099956904
        // validator 1 reward: 55,454153675 * 89% * (3/(3 + 1 + 1)) + 6,099956904 = 35,712474966
        // delegation reward: 35,712474966/3 = 11,904158322;    
        let reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("11.904158322136875638", "ether"));
        reward = await instance.getDelegationRewards.call(accounts[0], accounts[1]);
        assert.equal(reward.toString(), web3.utils.toWei("11.904158322136875638", "ether"));
        reward = await instance.getDelegationRewards.call(accounts[0], accounts[2]);
        assert.equal(reward.toString(), web3.utils.toWei("11.904158322136875638", "ether"));

        // delegation reward: 55,454153675 * 89% * (1/(3 + 1 + 1)) = 9,870839354
        reward = await instance.getDelegationRewards.call(accounts[1], accounts[1]);
        assert.equal(reward.toString(), web3.utils.toWei("9.870839354070017998", "ether"));

        // delegation reward: 55,454153675 * 89% * (1/(3 + 1 + 1)) = 9,870839354
        reward = await instance.getDelegationRewards.call(accounts[2], accounts[2]);
        assert.equal(reward.toString(), web3.utils.toWei("9.870839354070017998", "ether"));

        // rewards: 11,904158322 + 9,870839354 = 21,774997676 = valdition reward + delegation reward
        const rewards = await instance.getAllDelegatorRewards.call(accounts[2]);
        assert.equal(rewards.toString(), web3.utils.toWei("21.774997676206893636", "ether"));
        const rewards1 = await instance.getAllDelegatorRewards.call(accounts[0]);
        assert.equal(rewards1.toString(), web3.utils.toWei("11.904158322136875638", "ether"));
        const rewards2 = await instance.getAllDelegatorRewards.call(accounts[1]);
        assert.equal(rewards2.toString(), web3.utils.toWei("21.774997676206893636", "ether"));
    });

    it ("should not withdraw delegation rewards", async () => {
        const instance = await Staking.deployed();
    
        // check delegator not found
        await assertRevert(instance.withdrawReward(accounts[0], {from: accounts[6]}), "delegator not found");  
    });

    it ("should withdraw delegation rewards", async () => {
        const instance = await Staking.deployed();
        await instance.withdrawReward(accounts[0], {from: accounts[0]});

        // check delegator not found
        await assertRevert(instance.getDelegationRewards.call(accounts[0], accounts[6]), "delegation not found");

        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0", "ether"));

        await finalizeCommit([]);
        // previous block provision: 55,454153675
        // new block provision: 55,4541706 = annualProvision / blocksPerYear
        // delegation rewards: 55,4541706 * 89% * (1/5) + 9.870839354 = 19.7416817;
        reward = await instance.getDelegationRewards.call(accounts[2], accounts[2]);
        assert.equal(reward.toString(), web3.utils.toWei("19.741681722076097486", "ether"));
    });

    it ("calculate delegation rewards after withdraw reward", async () => {
        const instance = await Staking.deployed();

        // proposer base reward: 55.4541706068  *  (10+ 1)% = 6.09995876675
        // validator 1 reward: 55.4541706068 * 89% * (3/5) + 6.09995876675 = 35.7124858708
        // delegation reward: 35.7124858708/3 = 11.904161956;
        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("11.904161956921189495", "ether"));
    });

    it ("should withdraw commission rewards", async() => {
        const instance = await Staking.deployed();
        const commissionRate = web3.utils.toWei("0.5", "ether")
        const maxRate = web3.utils.toWei("1", "ether");
        await utils.advanceTime(86401);
        const bond3to3 = web3.utils.toWei("1", "ether");
        await instance.createValidator(commissionRate, maxRate, 0, 0, {from: accounts[3], value: bond3to3});

        // new block provision: 55,454154905
        await finalizeCommit([]);
        

        // validator rewards: 55,454154905 * 89% * (1/6) = 8,225699644
        // validate commission: 8,225699644 * 50% = 4,112849822
        let commission = await instance.getValidatorCommission.call(accounts[3]);
        assert.equal(commission.toString(), web3.utils.toWei("4.112852242475932477"));

        const reward = await instance.getDelegationRewards.call(accounts[3], accounts[3]);
        assert.equal(reward.toString(), web3.utils.toWei("4.112852242475932478", "ether"));

        // check validator not found
        await assertRevert(instance.withdrawValidatorCommission({from: accounts[6]}), "validator not found");  

        await instance.withdrawValidatorCommission({from: accounts[3]});

        var commissionCheck = await instance.getValidatorCommission.call(accounts[3]);
        assert.equal(commissionCheck.toString(), web3.utils.toWei("0"));

        // check no validator commission to reward
        await assertRevert(instance.withdrawValidatorCommission({from: accounts[3]}), "no validator commission to reward");
    });

    it ("calculate delegation reward after slash", async () => {
        const instance = await Staking.deployed();
        const bond6to6 = web3.utils.toWei("1", "ether");
        await instance.createValidator(0, 0, 0, 0, {from: accounts[6], value: bond6to6});

        // new block provision: 55.454154289583290000
        // delegation reward: 55.454154289583290000 * 89,142857143% * (1/6) = 8.23890292304
        await finalizeCommit([accounts[6]]);

        const missedBlocks = await instance.getMissedBlock.call(accounts[6]);
        assert.equal(missedBlocks[0], true);

        // new block provision: 55.454171221808730000
        // delegation reward: 55.454171221808730000 * 89,142857143% * (1/6) = 8.23890543868
        await finalizeCommit([accounts[6]]);

        // new block provision: 55.454188152925620000
        // delegation reward: 0
        await finalizeCommit([]);

        await utils.advanceTime(601);
        await instance.unjail({from: accounts[6]});

        // delegation reward: 55.4541881529256200005 * 89% * (0.9/5.9) = 7.54069541567
        await finalizeCommit([]);
        // total reward: 8.23890292304 + 8.23890543868 + 0 + 7.52861096748 = 24.0185037774;
        rewards = await instance.getDelegationRewards.call(accounts[6], accounts[6]);
        assert.equal(rewards.toString(), web3.utils.toWei("24.010829817464578594"));
    });

    it ("should not slash", async () => {
        const instance = await Staking.deployed();
        // validator not found
        await instance.doubleSign(accounts[4], 1000000000000, 10000);

        // check cannot slash infrations in the future
        await assertRevert(instance.doubleSign(accounts[1], 1000000000000, 10000))
    });

    it("should slash 50%", async () => {
        const instance = await Staking.deployed();
        const bond4to4 = web3.utils.toWei("1", "ether");
        await instance.createValidator(0, 0, 0, 0, {from: accounts[4], value: bond4to4});
        const tx = await instance.doubleSign(accounts[4], 1000000000000, 10);

        const validator = await instance.getValidator.call(accounts[4]);
        assert.equal(validator[0].toString(), web3.utils.toWei("0.5", "ether"));

        const slashEvents = await instance.getValidatorSlashEvents.call(accounts[4]);
        assert.equal(slashEvents[1][0].toString(), web3.utils.toWei("0.5", "ether"));
        assert.equal(slashEvents[0][0], tx.receipt.blockNumber);
    });

    it("should slash 100%", async () => {
        const instance = await Staking.deployed();
        await instance.doubleSign(accounts[4], 5000000000000, 10);
        const validator = await instance.getValidator.call(accounts[4]);
        assert.equal(validator[0].toString(), web3.utils.toWei("0", "ether"));
    });

    it("should slash unbonding delegation entries", async () => {
        const instance = await Staking.deployed();
        const bond5to5 = web3.utils.toWei("1", "ether");
        await instance.createValidator(0, 0, 0, 0, {from: accounts[5], value: bond5to5});

        const amount = web3.utils.toWei("0.1", "ether")
        const tx = await instance.undelegate(accounts[5], amount, {from: accounts[5]});
        await assertRevert(instance.doubleSign(accounts[5], 1000000000000, 0), "subtraction overflow");
        await assertRevert(instance.doubleSign(accounts[5], 1000000000000, 5000000000000), "cannot slash infrations in the future");

        // unbonding started before this height, stake did not contribute to infraction, skip it.
        await utils.advanceTime(1);
        await instance.doubleSign(accounts[5], 1000000000000, tx.receipt.blockNumber + 2);
        let udbEntries = await instance.getUBDEntries.call(accounts[5], accounts[5]);
        assert.equal(udbEntries[0][0].toString(), amount);
        // amount slashed: 9 - 10 * 50% = 4
        let validator = await instance.getValidator.call(accounts[5]);
        assert.equal(validator[0].toString(), web3.utils.toWei("0.40", "ether"));

        await utils.advanceTime(86401);
        await instance.doubleSign(accounts[5], 400000000000, 2);
        // unbonding delegation no longer eligible for slashing, skip it
        udbEntries = await instance.getUBDEntries.call(accounts[5], accounts[5]);
        assert.equal(udbEntries[0][0].toString(), amount);
        

        await instance.undelegate(accounts[5], amount, {from: accounts[5]});
        await instance.doubleSign(accounts[5], 200000000000, 2);
        udbEntries = await instance.getUBDEntries.call(accounts[5], accounts[5]);
        assert.equal(udbEntries[0][1].toString(), amount/2);

        // amount slashed: 2 - 2 * 50% - 0,5 = 0,5
        validator = await instance.getValidator.call(accounts[5]);
        assert.equal(validator[0].toString(), web3.utils.toWei("0.050000000000000000", "ether"));

        await instance.doubleSign(accounts[5], 200000000000, 2);
        // amount slashed: 0,5 - 2 * 50% - 0,25 = −0,75
        validator = await instance.getValidator.call(accounts[5]);
        assert.equal(validator[0].toString(), web3.utils.toWei("0", "ether"));
    });

    it ("should burn commission when delete validator", async () => {
        const instance = await Staking.deployed();
        const commissionRate = web3.utils.toWei("0.5", "ether")
        const maxRate = web3.utils.toWei("1", "ether");
        await utils.advanceTime(86401);
        const bond3to3 = web3.utils.toWei("1", "ether");
        await instance.createValidator(commissionRate, maxRate, 0, 0, {from: accounts[3], value: bond3to3});
        await finalizeCommit([]);
        //commission = 41.12850986669199418

        await instance.undelegate(accounts[3], web3.utils.toWei("1", "ether"), { from: accounts[3]});
        await utils.advanceTime(86401);
        
        // totalSupply = 5000000110.908324281326385627
        await instance.withdraw(accounts[3], {from: accounts[3]});
        const totalSupply = await instance.getTotalSupply.call();
        // totalSupply = totalSupply - commission = 5000000110.908324281326385627 - 41.12850986669199418 = 5000000106.7954732 
        assert.equal(totalSupply.toString(), web3.utils.toWei("5000000106.795473294657186209"));
    });

    it ("test validate signature", async () => {
        const instance = await Staking.deployed();
        const commissionRate = web3.utils.toWei("0.5", "ether")
        const maxRate = web3.utils.toWei("1", "ether");
        await utils.advanceTime(86401);
        const bond3to8 = web3.utils.toWei("1", "ether");
        await instance.createValidator(commissionRate, maxRate, 0, 0, {from: accounts[8], value: bond3to3});

        await finalizeCommit([accounts[8]]);
        let missedBlocks = await instance.getMissedBlock.call(accounts[8]);
        assert.equal(missedBlocks[0], true);
        await finalizeCommit([]);
        await finalizeCommit([]);
        missedBlocks = await instance.getMissedBlock.call(accounts[8]);
        assert.equal(missedBlocks[0], false);
    });

    it ("should not unjail", async() => {
        const instance = await Staking.deployed();

        // validator not found
        await assertRevert(instance.unjail({from: accounts[7]}), "validator not found");

        const bond6to6 = web3.utils.toWei("1", "ether");
        const minSelfDelegation = web3.utils.toWei("0.9", "ether");
        await instance.createValidator(0, 0, 0, minSelfDelegation, {from: accounts[7], value: bond6to6});

        // validator not jailed
        await assertRevert(instance.unjail({from: accounts[7]}), "validator not jailed");

        // slash and jail
        await finalizeCommit([accounts[7]]);
        await finalizeCommit([accounts[7]]);
        await finalizeCommit([accounts[7]]);

        const validator = await instance.getValidator.call(accounts[7]);
        assert.equal(validator[2], true);

        // validator jailed
        await assertRevert(instance.unjail({from: accounts[7]}), "validator jailed");

        // self delegation too low to unjail
        await instance.undelegate(accounts[7], web3.utils.toWei("0.5", "ether"), {from: accounts[7]});
        await assertRevert(instance.unjail({from: accounts[7]}), "validator jailed");
        await utils.advanceTime(601);
        await assertRevert(instance.unjail({from: accounts[7]}), "self delegation too low to unjail");
    });

    it ("should jail when self delegation too low", async () => {
        const instance = await Staking.deployed();
        const bond6to6 = web3.utils.toWei("2", "ether");
        const minSelfDelegation = web3.utils.toWei("1", "ether");
        await instance.createValidator(0, 0, 0, minSelfDelegation, {from: accounts[8], value: bond6to6});
        await instance.undelegate(accounts[8], web3.utils.toWei("1.5", "ether"), {from: accounts[8]});
        const validator = await instance.getValidator.call(accounts[8]);
        assert.equal(validator[2], true);
    })


    it ("should mint", async () => {
        const instance = await Staking.deployed();
        await instance.setMintParams(0,0,5,0,0);
        const totalSupply = web3.utils.toWei("1000", "ether");
        const totalBonded = web3.utils.toWei("1", "ether");
        await instance.setTotalSupply(totalSupply);
        await instance.setTotalBonded(totalBonded);
        await instance.setInflation(0);
        await instance.setAnnualProvision(0);

        await instance.mint();

        // inflation min
        let inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.07", "ether")) // 7%

        const blockProvision = await instance.getBlockProvision.call();
        // 1000 * 7% / 5 = 14
        assert.equal(blockProvision.toString(),  web3.utils.toWei("14.000000000000000000", "ether"));

        await instance.mint();
        
        inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.095961729812476081", "ether"))

        await mint(5);

        // inflation max: 20%
        inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.2", "ether"));

        await instance.setTotalSupply(totalSupply);
        await instance.setTotalBonded(totalSupply);
        await instance.mint();

        inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.187194029850746269", "ether"));

        
        await mint(5); // 1 year
        let newTotalSupply = await instance.getTotalSupply.call();
        await instance.setTotalBonded(newTotalSupply.toString());

        await mint(5); // 1 year
        newTotalSupply = await instance.getTotalSupply.call();
        await instance.setTotalBonded(newTotalSupply.toString());

        await mint(5); // 1 year


        // inflation min : 7%
        inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.07", "ether")) // 7%
    });

    it ("should delegator stake", async () => {
        const instance = await Staking.deployed();

        // check delegation not found
        await assertRevert(instance.getDelegatorStake(accounts[6], accounts[6]), "delegation not found");

        var stake = await instance.getDelegatorStake(accounts[0], accounts[0]);
        assert.equal(stake.toString(), web3.utils.toWei("1", "ether"));
    });

    it ("should all delegator stake", async () => {
        const instance = await Staking.deployed();

        var stake = await instance.getAllDelegatorStake(accounts[1]);
        assert.equal(stake.toString(), web3.utils.toWei("2", "ether"));
    });

})