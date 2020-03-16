const Staking = artifacts.require("Staking");


function wait(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

contract("Staking", async (accounts) => {
    const feeCollected = web3.utils.toWei("1", "ether");

    async function finalizeCommit(signed) {
        let instance = await Staking.deployed();
        await instance.finalizeCommit(accounts[0], [accounts[0]], [signed], [200], feeCollected)
    }

    it("should create new validator", async () => {
        let instance = await Staking.deployed();

        const bond = web3.utils.toWei("100", "ether")
        await instance.createValidator(0,1, {from: accounts[0], value: bond});
        let validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[0]);
        assert.equal(validatorSet[1][0], bond);

        const bond2 = web3.utils.toWei("101", "ether")
        await instance.createValidator(0,1, {from: accounts[1], value: bond2});
        validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[1]);
        assert.equal(validatorSet[1][0], bond2);

        const bond3 = web3.utils.toWei("1", "ether")
        await instance.createValidator(0,1, {from: accounts[2], value: bond3});
        validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][2], accounts[2]);
        assert.equal(validatorSet[1][2], bond3);
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
        assert.equal(validatorSet[1][0], web3.utils.toWei("200", "ether"));

        const stake = await instance.getDelegationStake.call(accounts[1], accounts[0]);
        assert.equal(stake.toString(), web3.utils.toWei("100", "ether"));
    })

    it("should withdrawl delegation reward", async () => {
        let instance = await Staking.deployed();
        let reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward, 0);

        await finalizeCommit(true)
        await finalizeCommit(true)

        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0.5", "ether"));

        await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});


        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), "0");

        await finalizeCommit(true)

        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0.5", "ether"));

        
        reward = await instance.getDelegationRewards.call(accounts[1], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("1", "ether"));
    })
    
    it("should withdrawl commission rewards", async() => {
        const instance = await Staking.deployed();
        // commission rate: 1%
        await instance.updateValidator(web3.utils.toWei("0.01", "ether"), 0)

        await finalizeCommit(true)

        reward = await instance.getValidatorCommissionReward.call(accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0.01", "ether"));

        await instance.withdrawValidatorCommissionReward({from: accounts[0]});

        reward = await instance.getValidatorCommissionReward.call(accounts[0]);
        assert.equal(reward.toString(), "0");
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

        await wait(2000);
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
        const boud2to0 = web3.utils.toWei("10", "ether");
        await instance.delegate(accounts[0], {from:accounts[2], value: boud2to0})
        let stake = await instance.getDelegationStake.call(accounts[2], accounts[0]);
        assert.equal(stake.toString(), boud2to0);

        // update maxMissed block
        await instance.setParams(0, 2, 1, 0,0, 0, 0, 0);
        await finalizeCommit(false);

        let val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], false);

        await finalizeCommit(false);
        val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], true);


        stake = await instance.getDelegationStake.call(accounts[2], accounts[0]);
        assert.equal(stake.toString(), web3.utils.toWei("9", "ether"));

    });

    it("should unjail validator", async () => {
        const instance = await Staking.deployed();

        let validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[1]);

        await wait(2000);
        await instance.unjail({from: accounts[0]});
        val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], false);

        validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[0]);
    })
})