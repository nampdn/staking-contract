const Staking = artifacts.require("Staking");
contract("Staking", async (accounts) => {
    it("should create new validator", async () => {
        let instance = await Staking.deployed();
        const bond = 10 * Math.pow(10, 18)
        await instance.createValidator(0,1, {from: accounts[0], value: bond});
        const validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[0]);
        assert.equal(validatorSet[1][0], bond);
    })


    it("should delegate to validator", async () => {
        let instance = await Staking.deployed();
        const bond = 10 * Math.pow(10, 18)
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
        assert.equal(reward.toString(), "500000000000000000");

        await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});


        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), "0");

        await instance.finalizeCommit(accounts[0], [accounts[0]], [true], [200])

        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), "500000000000000000");

        
        reward = await instance.getDelegationRewards.call(accounts[1], accounts[0]);
        assert.equal(reward.toString(), "1000000000000000000");
    })
})