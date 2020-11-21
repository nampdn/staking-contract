const Staking = artifacts.require("Staking");
const Validator = artifacts.require("Validator");
contract("Staking", async (accounts) => {
    
    it("should create validator", async () => {
        const instance = await Staking.deployed();
        const rate = web3.utils.toWei("0.4", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");
        const minSelfDelegation = web3.utils.toWei("0.5", "ether");
        const name = web3.utils.fromAscii("val1");
        await instance.createValidator(name, rate, maxRate, maxChangeRate, minSelfDelegation, {from: accounts[0]})
        const total = await instance.allValsLength()
        assert.equal(total, 1);
    })

    it("finalize", async() => {
        const instance = await Staking.deployed();
        const contractAddr = await instance.allVals(0)
        const validator = await Validator.at(contractAddr)
        await instance.mint({from: accounts[0]});
        await validator.delegate({from: accounts[0], value: web3.utils.toWei("0.4", "ether")})
        await instance.setPreviousProposer(accounts[0]);
        const validatorSet = await instance.getValidatorSets.call();
        let signed = validatorSet[0].map(_ =>  true);
        // block rewards: 39,63723998
        await web3.eth.sendTransaction({from: accounts[7], to: instance.address, value: web3.utils.toWei("60", "ether")});

        await instance.finalize(validatorSet[0], validatorSet[1], signed)
        const commission = await validator.getCommissionRewards.call()
        assert.equal(commission.toString(), web3.utils.toWei("15.854895991882293251", "ether"))
        const delegationRewards = await validator.getDelegationRewards.call(accounts[0])
        assert.equal(delegationRewards.toString(), web3.utils.toWei("23.782343987823439878", "ether"))
    })

    it("should get all validators of the delegator", async () => {
        const instance = await Staking.deployed();
        const contractAddr = await instance.allVals(0)
        const vals = await instance.getValidatorsByDelegator.call(accounts[0])
        assert.equal(vals[0], contractAddr)
    })

    it("double sign", async () => {
        const instance = await Staking.deployed();
        await instance.doubleSign(accounts[0], 1000, 5);
        const validatorSet = await instance.getValidatorSets.call();
        assert.equal(validatorSet[0].length, 0)
        const contractAddr = await instance.allVals(0)
        const validator = await Validator.at(contractAddr)
        const info = await validator.inforValidator()
        assert.equal(info.jailed, true)
        assert.equal(info.tokens.toString(), web3.utils.toWei("0.399999995000000000", "ether"))
        const slashEvent = await validator.slashEvents(0)
        assert.equal(slashEvent.fraction.toString(), web3.utils.toWei("0.000000012500000000", "ether"))
    });
})