const { assertRevert } = require("./utils");

const Staking = artifacts.require("StakingTest");
const Minter = artifacts.require("Minter");


contract("Minter", async (accounts) => {

    it("mint", async () => {
        const staking = await Staking.deployed();
        await staking.createMinterTest();
        const minter = await Minter.at(await staking.minter())
        await staking.mint();
        const inflation = await minter.inflation()
        assert.equal(inflation.toString(), web3.utils.toWei("0.05", "ether"))
        const annualProvision = await minter.annualProvision();
        assert.equal(annualProvision.toString(), web3.utils.toWei("250000000", "ether"))
        const feesCollected = await minter.feesCollected();
        assert.equal(feesCollected.toString(), web3.utils.toWei("50000000.000000000000000000", "ether"))
    })

    it("not mint", async () => {
        const staking = await Staking.deployed();
        await staking.transferOwnership(accounts[1], {from: accounts[0]})
        await assertRevert(staking.mint(), "Reason given: Ownable: caller is not the owner.")
    })
})