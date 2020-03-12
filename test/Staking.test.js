const Staking = artifacts.require("Staking");
contract("Staking", async (accounts) => {
    it("should create new validator", async () => {
        let instance = await Staking.deployed();
        const bond = web3.utils.toWei("100", "ether")
        await instance.createValidator(0,1, {from: accounts[0], value: bond});
        const validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[0]);
        assert.equal(validatorSet[1][0], bond);
    })


    it("should delegate to validator", async () => {
        let instance = await Staking.deployed();
        const bond = web3.utils.toWei("100", "ether")
        await instance.delegate(accounts[0], {from:accounts[1], value: bond})

        const validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[1][0], bond * 2);

        
    })

    it("should withdrawl delegation reward", async () => {
        let instance = await Staking.deployed();
        let reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward, 0);

        await instance.finalizeCommit(accounts[0], [accounts[0]], [true], [200])
        await instance.finalizeCommit(accounts[0], [accounts[0]], [true], [200])

        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0.5", "ether"));

        await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});


        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), "0");

        await instance.finalizeCommit(accounts[0], [accounts[0]], [true], [200])

        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0.5", "ether"));

        
        reward = await instance.getDelegationRewards.call(accounts[1], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("1", "ether"));
    })
    
    it("should withdrawl commission rewards", async() => {
        const instance = await Staking.deployed();
        // commission rate: 1%
        await instance.updateValidator(web3.utils.toWei("0.01", "ether"), 0)

        await instance.finalizeCommit(accounts[0], [accounts[0]], [true], [200])

        reward = await instance.getValidatorCommissionReward.call(accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0.01", "ether"));

        await instance.withdrawValidatorCommissionReward({from: accounts[0]});

        reward = await instance.getValidatorCommissionReward.call(accounts[0]);
        assert.equal(reward.toString(), "0");
    })

    it("should undelegate", async () => {
        const instance = await Staking.deployed();
        let stake = await instance.getDelegationStake.call(accounts[1], accounts[0])
        assert.equal(stake.toString(), web3.utils.toWei("100", "ether"));

        await instance.undelegate(accounts[0], {from: accounts[1]});

        stake = await instance.getDelegationStake.call(accounts[1], accounts[0])
        assert.equal(stake.toString(), web3.utils.toWei("0", "ether"));

        reward = await instance.getDelegationRewards.call(accounts[1], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0", "ether"));
    })

    it ("should jail validator", async() => {
        const instance = await Staking.deployed();
        const boud2to0 = web3.utils.toWei("10", "ether");
        await instance.delegate(accounts[0], {from:accounts[2], value: boud2to0})
        let stake = await instance.getDelegationStake.call(accounts[2], accounts[0]);
        assert.equal(stake.toString(), boud2to0);

        // update maxMissed block
        await instance.setParams(0, 3, 1, 0,0, 0);
        await instance.finalizeCommit(accounts[0], [accounts[0]], [false], [200]);

        let val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], false);

        await instance.finalizeCommit(accounts[0], [accounts[0]], [false], [200]);
        val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], true);


        stake = await instance.getDelegationStake.call(accounts[2], accounts[0]);
        assert.equal(stake.toString(), web3.utils.toWei("9", "ether"));

    });

    it("should unjail validator", async () => {
        const instance = await Staking.deployed();
        await instance.unjail({from: accounts[0]});

        const val = await instance.getValidator.call(accounts[0]);
        assert.equal(val[1], false);
    })
})