const Staking = artifacts.require("StakingTest");
const Validator = artifacts.require("Validator");
const utils = require("./utils");

contract("Staking", async (accounts) => {    
    it("should create validator", async () => {
        const instance = await Staking.deployed();
        const rate = web3.utils.toWei("0.4", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");
        const name = web3.utils.fromAscii("val1");
        await instance.createValidator(name, rate, maxRate, maxChangeRate, {from: accounts[0]})
        await utils.assertRevert(instance.createValidator(name, rate, maxRate, maxChangeRate, {from: accounts[0]}), "Valdiator owner exists") 
        await instance.transferOwnership(accounts[0])
        assert.equal(await instance.allValsLength(), 1);
    })

    it ("should not create validator", async() => {
        const instance = await Staking.deployed();
        const bond = web3.utils.toWei("1", "ether")
        const testCases = [
            {
                rate: 0,
                maxRate: web3.utils.toWei("1.1", "ether"),
                maxChangeRate: 0,
                from: accounts[5],
                value: bond,
                message: "commission max rate cannot be more than 100%"
            },
            {
                rate: web3.utils.toWei("1", "ether"),
                maxRate: web3.utils.toWei("0.9", "ether"),
                maxChangeRate: 0,
                from: accounts[5],
                value: bond,
                message: "commission rate cannot be more than the max rate"
            },
            {
                rate: 0,
                maxRate: web3.utils.toWei("0.9", "ether"),
                maxChangeRate: web3.utils.toWei("1", "ether"),
                from: accounts[5],
                value: bond,
                message: "commission max change rate can not be more than the max rate"
            }
        ];

        const name = web3.utils.fromAscii("val5");

        for(var testCase of testCases) {
            await utils.assertRevert(instance.createValidator(name, testCase.rate, testCase.maxRate, testCase.maxChangeRate, {from: testCase.from}), 
                "Returned error: VM Exception while processing transaction: revert");
        }
    })

    it("finalize", async() => {
        const instance = await Staking.deployed();
        await instance.setValidatorParams(600, web3.utils.toWei("0.0001", "ether"), 1814400, web3.utils.toWei("0.05", "ether"), 
        100000, web3.utils.toWei("0.5", "ether"), web3.utils.toWei("0.01", "ether"), web3.utils.toWei("0.1", "ether"))
        const contractAddr = await instance.allVals(0)
        const validator = await Validator.at(contractAddr)
        await instance.mint({from: accounts[0]});
        await validator.delegate({from: accounts[0], value: web3.utils.toWei("0.4", "ether")})
        await validator.start();
        await instance.setPreviousProposer(accounts[0]);
        const validatorSet = await instance.getValidatorSets.call();
        let signed = validatorSet[0].map(_ =>  true);
        // block rewards: 39,63723998
        await instance.deposit({accounts: accounts[7], value: web3.utils.toWei("60", "ether")})
        await instance.finalize(validatorSet[0], validatorSet[1], signed)
        const commission = await validator.getCommissionRewards.call()
        assert.equal(commission.toString(), web3.utils.toWei("3.170979198376458649", "ether"))
        const delegationRewards = await validator.getDelegationRewards.call(accounts[0])
        assert.equal(delegationRewards.toString(), web3.utils.toWei("4.756468797564687976", "ether"))
    })

    it("should get all validators of the delegator", async () => {
        const instance = await Staking.deployed();
        const contractAddr = await instance.allVals(0)
        const vals = await instance.getValidatorsByDelegator.call(accounts[0])
        assert.equal(vals[0], contractAddr)
    })

    it("should not double sign", async () => {
        const instance = await Staking.deployed();
        await utils.assertRevert(instance.doubleSign(accounts[0], 1000, 5, {from: accounts[1]}), "Ownable: caller is not the owner")
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
        assert.equal(info.tokens.toString(), web3.utils.toWei("0.399999500000000000", "ether"))
        const slashEvent = await validator.slashEvents(0)
        assert.equal(slashEvent.fraction.toString(), web3.utils.toWei("0.00000125", "ether"))

        var totalSlashedToken = await instance.totalSlashedToken()
        assert.equal(web3.utils.toWei("0.0000005", "ether"), totalSlashedToken.toString())
    });
})