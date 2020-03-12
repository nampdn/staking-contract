const Staking = artifacts.require("Staking");
contract("Staking", async (accounts) => {
    it("should create new validator", async () => {
        let instance = await Staking.deployed();
        await instance.createValidator(0,1, {from: accounts[0], value: 100});
        const validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[0][0], accounts[0]);
        assert.equal(validatorSet[1][0], 100);
    })


    it("should delegate to validator", async () => {
        let instance = await Staking.deployed();
        await instance.delegate(accounts[0], {from:accounts[1], value: 100})

        const validatorSet = await instance.getCurrentValidatorSet.call();
        assert.equal(validatorSet[1][0], 200);
    })

    it("should withdrawl delegation reward", async () => {
        let instance = await Staking.deployed();
        let reward = await instance.withdrawDelegationReward.call(accounts[0]);
        assert.equal(reward, 0);

        await instance.finalizeCommit(accounts[0], [accounts[0]], [true], [200])
        await instance.finalizeCommit(accounts[0], [accounts[0]], [true], [200])

        reward = await instance.withdrawDelegationReward.call(accounts[0]);
        assert.equal(reward.toString(), 1);
    })
})