const Staking = artifacts.require("StakingTest");
const Validator = artifacts.require("Validator");
const utils = require("./utils");
const Params = artifacts.require("Params");

contract("Staking", async (accounts) => {    

    async function createValidator(account) {
        const instance = await Staking.deployed();
        const rate = web3.utils.toWei("0.4", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");
        const name = web3.utils.fromAscii("val1");
        var selfDelegate =  web3.utils.toWei("0.1", "ether");
        return instance.createValidator(name, rate, maxRate, maxChangeRate, {from: account, value: selfDelegate})
    }

    it("should create validator", async () => {
        const instance = await Staking.deployed();
        await instance.createParamsTest();

        const rate = web3.utils.toWei("0.4", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");
        const name = web3.utils.fromAscii("val1");
        var selfDelegate =  web3.utils.toWei("0.2", "ether");
        await instance.createValidator(name, rate, maxRate, maxChangeRate, {from: accounts[0], value: selfDelegate})
        await utils.assertRevert(instance.createValidator(name, rate, maxRate, maxChangeRate, {from: accounts[0]}), "Valdiator owner exists") 
        await instance.transferOwnership(accounts[0])
        var valAddr = await instance.getAllValidator()
        assert.equal(await instance.allValsLength(), valAddr.length);
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
            },
            {
                rate: 0,
                maxRate: web3.utils.toWei("0.9", "ether"),
                maxChangeRate: web3.utils.toWei("1", "ether"),
                from: accounts[5],
                value: web3.utils.toWei("0.001", "ether"),
                message: "self delegation below minimum"
            }
        ];

        const name = web3.utils.fromAscii("val5");

        for(var testCase of testCases) {
            await utils.assertRevert(instance.createValidator(name, testCase.rate, testCase.maxRate, testCase.maxChangeRate, {from: testCase.from, value: testCase.value}), 
                "Returned error: VM Exception while processing transaction: revert");
        }
    })

    async function createParamProposal() {
        const staking = await Staking.deployed();
        const params = await Params.at(await staking.params());
        await params.addProposal([3, 4, 5, 6, 7, 8, 9, 10, 11, 12], [
            600, 
            web3.utils.toWei("0.0001", "ether"), 
            1814400, 
            web3.utils.toWei("0.05", "ether"), 
            100000, 
            web3.utils.toWei("0.5", "ether"), 
            web3.utils.toWei("0.01", "ether"), 
            web3.utils.toWei("0.1", "ether"), 
            web3.utils.toWei("0.1", "ether"), 
            web3.utils.toWei("0.1", "ether")
        ]
        , {from: accounts[0], value: web3.utils.toWei("1", "ether")})
        await params.confirmProposal(0);
    }

    it("finalize", async() => {
        const instance = await Staking.deployed();
        await createParamProposal();
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
        assert.equal(delegationRewards.toString(), web3.utils.toWei("4.756468797564687975", "ether"))
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
        assert.equal(info.tokens.toString(), web3.utils.toWei("0.5999995", "ether"))
        const slashEvent = await validator.slashEvents(0)
        assert.equal(slashEvent.fraction.toString(), web3.utils.toWei("0.000000833333333333", "ether"))

        var totalSlashedToken = await instance.totalSlashedToken()
        assert.equal(web3.utils.toWei("0.0000005", "ether"), totalSlashedToken.toString())

        var treasury = await instance.treasury();
        var treasuryBalance = await web3.eth.getBalance(treasury);
        assert.equal(web3.utils.toWei("0.0000005", "ether"), treasuryBalance.toString())
    });

    it("start/stop validator", async () => {
        const staking = await Staking.deployed();
        await createValidator(accounts[1])
        const valAddr = await staking.allVals.call(1);
        const val = await  Validator.at(valAddr);
        await val.delegate({from: accounts[1], value: web3.utils.toWei("1", "ether")});

        // start validator
        await val.start({from: accounts[1]});
        let valSets = await staking.getValidatorSets.call();
        assert.equal(valSets[0].length, 1)
        assert.equal(valSets[0][0], accounts[1])

        allVals1 = await staking.allValsLength();
        assert.equal(allVals1.toString(), "2")

        // stop validator
        await val.undelegate({from: accounts[1]})
        valSets = await staking.getValidatorSets.call();
        assert.equal(valSets[0].length, 0)

        allVals = await staking.allValsLength();
        assert.equal(allVals.toString(), "1")

        valOf2 = await staking.valOf(valAddr)
        assert.equal("0x0000000000000000000000000000000000000000", valOf2.toString())
    })
})