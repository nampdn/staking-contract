const Staking = artifacts.require("Staking");
const utils = require("./utils");


contract("Staking", async (accounts) => {
    const powerReduction = Math.pow(10, 6);
    async function finalizeCommit(signed) {
        let instance = await Staking.deployed();
        const validatorSet = await instance.getCurrentValidatorSet.call();
        await instance.mint();
        await instance.finalizeCommit(accounts[0], validatorSet[0], [signed, true, true], validatorSet[1])
    }

    it("should create new validator", async () => {
        let instance = await Staking.deployed();
        const maxRate = web3.utils.toWei("0.1", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");

        const bond = web3.utils.toWei("100", "ether")
        await instance.createValidator(0, maxChangeRate, maxRate ,0 , "val1", "val.com", "val1@gmail.com", "val1", {from: accounts[0], value: bond});
        let validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[0]);
        assert.equal(validatorSet[1][0].toString(), bond/powerReduction);

        const bond2 = web3.utils.toWei("101", "ether")
        await instance.createValidator(0,maxChangeRate, maxRate,0, "val1", "val.com", "val1@gmail.com", "val1", {from: accounts[1], value: bond2});
        validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[1]);
        assert.equal(validatorSet[1][0].toString(), bond2/powerReduction);

        const bond3 = web3.utils.toWei("1", "ether")
        await instance.createValidator(0,maxChangeRate, maxRate,0, "val1", "val.com", "val1@gmail.com", "val1", {from: accounts[2], value: bond3});
        validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][2], accounts[2]);
        assert.equal(validatorSet[1][2].toString(), bond3/powerReduction);
    })


    it("should delegate to validator", async () => {
        let instance = await Staking.deployed();
        const bond = web3.utils.toWei("0.1", "ether")
        await instance.delegate(accounts[0], {from:accounts[1], value: bond})

        let validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[1]);

        const bond2 = web3.utils.toWei("99.9", "ether")
        await instance.delegate(accounts[0], {from:accounts[1], value: bond2})
        validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[0]);
        assert.equal(validatorSet[1][0], web3.utils.toWei("200", "ether")/powerReduction);

        const stake = await instance.getDelegationStake.call(accounts[1], accounts[0]);
        assert.equal(stake.toString(), web3.utils.toWei("100", "ether"));
    })

    it("should withdrawl delegation reward", async () => {
        // // feeCollected = 7% * 5000000000/6311520 = 55,454153675
        // rewards:
        // pr: 55,454153675 *  (10% + 1%) = 5,600869521
        // v1r: 55,454153675 * 89% * (200/(200 + 101 + 1)) = 32,684898524 + 5,600869521 = 38,285768045
        //    - del1: 88,139052199/2 = 19,142884022


        let instance = await Staking.deployed();
        let reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward, 0);

        await finalizeCommit(true)
        await finalizeCommit(true)

        const feeCollected = await instance.getBlockProvision.call();
        assert.equal(feeCollected.toString(), web3.utils.toWei("554.541536745506629147", "ether"))


        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("193.924277138056142500", "ether"));

        await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});


        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), "0");

        await finalizeCommit(true)

        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("193.924284659381195200", "ether"));

        
        reward = await instance.getDelegationRewards.call(accounts[1], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("387.848561797437337700", "ether"));

        
    })
    
    it("should withdrawl commission rewards", async() => {
        const instance = await Staking.deployed();
        await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});
        await utils.advanceTime(86402);
        // newcommission rate: 1%
        await instance.updateValidator(web3.utils.toWei("0.01", "ether"), 0, "", "", "", "")

        await finalizeCommit(true)

        reward = await instance.getValidatorCommissionReward.call(accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0.006994039735099337", "ether"));

        await instance.withdrawValidatorCommissionReward({from: accounts[0]});

        reward = await instance.getValidatorCommissionReward.call(accounts[0]);
        assert.equal(reward.toString(), "0");

        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0.346204966887417200", "ether"));

    })

    it("should undelegate", async () => {
        const instance = await Staking.deployed();
        const boud3to0 = web3.utils.toWei("100", "ether");
        await instance.delegate(accounts[0], {from: accounts[3], value: boud3to0})

        let stake = await instance.getDelegationStake.call(accounts[3], accounts[0])
        assert.equal(stake.toString(), boud3to0);

        await instance.undelegate(accounts[0], String(boud3to0/2), {from: accounts[3]});

        stake = await instance.getDelegationStake.call(accounts[3], accounts[0])
        assert.equal(stake.toString(), boud3to0/2);

        await instance.undelegate(accounts[0], String(boud3to0/2), {from: accounts[3]});
        stake = await instance.getDelegationStake.call(accounts[3], accounts[0])
        assert.equal(stake.toString(), "0");

        reward = await instance.getDelegationRewards.call(accounts[3], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0", "ether"));
    })

    it("should withdraw", async() => {
        const instance = await Staking.deployed();

        let udb = await instance.getUnboudingDelegation.call(accounts[3], accounts[0])
        assert.equal(udb[0], 0)
        assert.equal(udb[1].toString(), web3.utils.toWei("100", "ether"))

        await utils.advanceTime(2000);
        await finalizeCommit(true);
        udb = await instance.getUnboudingDelegation.call(accounts[3], accounts[0])
        assert.equal(udb[0].toString(), web3.utils.toWei("100", "ether"))
        assert.equal(udb[1].toString(), web3.utils.toWei("100", "ether"))

        await instance.withdraw(accounts[0], {from: accounts[3]});
        udb = await instance.getUnboudingDelegation.call(accounts[3], accounts[0])
        assert.equal(udb[0], 0)
        assert.equal(udb[1], 0)
    })

    it ("should jail validator", async() => {
        const instance = await Staking.deployed();
        // update maxMissed block
        await instance.setParams(0, 2, 1, 0,0, 0, 0, 0);
        await finalizeCommit(false);

        let val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], false);

        await finalizeCommit(false);
        val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], true);


        stake = await instance.getDelegationStake.call(accounts[0], accounts[0]);
        assert.equal(stake.toString(), web3.utils.toWei("90", "ether"));
        
        let validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0].length, 2);


    });

    it("should unjail validator", async () => {
        const instance = await Staking.deployed();

        let validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[1]);

        await utils.advanceTime(2000);
        await instance.unjail({from: accounts[0]});
        val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], false);
        assert.equal(val[0].toString(), web3.utils.toWei("180", "ether"));

        validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[0]);
    })

    it ("should check delegation reward after unjail", async () => {
        // rewards:
        // pr: 1 *  (10% + 1%) = 0.11
        // v1r: 1 * 89% * (180/(180 + 101 + 1)) = 0,568085106 + 0.11 = 0,678085106 - 0,678085106 * 1% = 0,335652127
        //    - del1: 0,671304255/2 = 0,339042553
        //    - del2 = del1
        // c2r: 1 * 89% * (101/(180 + 101 + 1)) = 0,318758865
        // c3r: 1 * 89% * (1/(180 + 101 + 1)) = 0,003156028

        const instance = await Staking.deployed();
        await instance.withdrawValidatorCommissionReward({ from: accounts[0]})
        await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});
        await instance.withdrawDelegationReward(accounts[0], {from: accounts[1]});
        await instance.withdrawDelegationReward(accounts[1], {from: accounts[1]});
        await instance.withdrawDelegationReward(accounts[2], {from: accounts[2]});

        await finalizeCommit(true);

        // v1:d1
        let reward = await instance.getDelegationRewards.call(accounts[0], accounts[0])
        assert.equal(reward.toString(), web3.utils.toWei("0.335652127659574380", "ether"));

        // v1:d2
        reward = await instance.getDelegationRewards.call(accounts[1], accounts[0])
        assert.equal(reward.toString(), web3.utils.toWei("0.335652127659574380", "ether"));

        // val 1
        let commission = await instance.getValidatorCommissionReward.call(accounts[0]);
        assert.equal(commission.toString(), web3.utils.toWei("0.006780851063829787", "ether"));

        // v2:d1
        reward = await instance.getDelegationRewards.call(accounts[1], accounts[1])
        assert.equal(reward.toString(), web3.utils.toWei("0.318758865248226926", "ether"));

        // v3:d1
        reward = await instance.getDelegationRewards.call(accounts[2], accounts[2])
        assert.equal(reward.toString(), web3.utils.toWei("0.003156028368794325", "ether"));

    })

    it("should check doubleSign", async () => {
        const instance = await Staking.deployed();
        const boud4to0 = web3.utils.toWei("10", "ether");
        await instance.delegate(accounts[0], {from:accounts[4], value: boud4to0})
        await instance.doubleSign(accounts[0], 1000); 
        let stake = await instance.getDelegationStake.call(accounts[4], accounts[0]);
        assert.equal(stake.toString(), String(boud4to0/2));

        await utils.advanceTime(2000);
        await instance.unjail({from: accounts[0]});
    })

    it("should check slash unbounding delegation entries", async () => {
        const instance = await Staking.deployed();
        await instance.undelegate(accounts[0], web3.utils.toWei("5", "ether"), {from : accounts[4]});
        await instance.doubleSign(accounts[0], 1000); 
        const udb = await instance.getUnboudingDelegation.call(accounts[4], accounts[0])
        assert.equal(udb[1].toString(), web3.utils.toWei("2.5", "ether"))
    })

    it("should check delete delegation and validator when all undelgation is completed", async() => {
        const instance = await Staking.deployed();
        const boud = web3.utils.toWei("1", "ether")
        await instance.createValidator(0,0, 0,0, "val1", "val.com", "val1@gmail.com", "val1", {from: accounts[6], value: boud});
        await instance.undelegate(accounts[6], boud, {from : accounts[6]});
        await utils.advanceTime(2000);
        await instance.withdraw(accounts[6], {from: accounts[6]});

        await instance.createValidator(0,0, 0,0, "val1", "val.com", "val1@gmail.com", "val1", {from: accounts[6], value: boud});
    });
})