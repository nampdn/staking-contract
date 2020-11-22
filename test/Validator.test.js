const Validator = artifacts.require("Validator");
const Staking = artifacts.require("Staking");
const Minter = artifacts.require("Minter");
const utils = require("./utils");

contract("Validator", async (accounts) => {
    async function finalize(notSigned) {
        notSigned = notSigned  || [];
        let instance = await Staking.deployed();
        const validatorSet = await instance.getValidatorSets.call();
        await instance.mint();
        const minter = await Minter.at(await instance.minter())
        const blockProvision = await minter.getBlockProvision();
        await instance.deposit({from: accounts[0], value: blockProvision.toString()})
        await instance.setPreviousProposer(accounts[0]);
        let signed = validatorSet[0].map(addr => notSigned.indexOf(addr) === -1);
        await instance.finalize(validatorSet[0], validatorSet[1], signed)
    }

    
    it("should create validator", async () => {
        const instance = await Validator.deployed();

        const rate = web3.utils.toWei("0.4", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");
        const minSelfDelegation = web3.utils.toWei("0.5", "ether");
        const name = web3.utils.fromAscii("val1");
        await instance.initialize(name, accounts[0], rate, maxRate, maxChangeRate, minSelfDelegation, {from: accounts[0]});

        var inforValidator = await instance.inforValidator({from: accounts[0]});
        var commission = await instance.commission({from: accounts[0]});

        var expectedName = inforValidator.name;
        var expectedRate = commission.rate;
        var expectedMaxRate = commission.maxRate;
        var expectedMaxChangeRate = commission.maxChangeRate;
        var expectedMinselfDelegation = inforValidator.minSelfDelegation;

        assert.equal("val1", web3.utils.toAscii(expectedName).toString().replace(/\0/g, ''));
        assert.equal(rate, expectedRate.toString());
        assert.equal(maxRate, expectedMaxRate.toString());
        assert.equal(maxChangeRate, expectedMaxChangeRate.toString());
        assert.equal(minSelfDelegation, expectedMinselfDelegation.toString());
    })

    it ("should not create validator", async() => {
        const instance = await Validator.deployed();
        const bond = web3.utils.toWei("1", "ether")
        const testCases = [
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
            }
        ];

        const name = web3.utils.fromAscii("val5");

        for(var testCase of testCases) {
            await utils.assertRevert(instance.initialize(name, accounts[5], testCase.rate, testCase.maxRate, testCase.maxChangeRate ,
                testCase.minSelfDelegation, {from: testCase.from, value: testCase.value}), 
                "Returned error: VM Exception while processing transaction: revert");
        }
    })

    it ("should not update validator", async () => {
        const instance = await Validator.deployed();
        const name = web3.utils.fromAscii("");
        commissionRate = web3.utils.toWei("2", "ether");
        await utils.assertRevert(instance.update(name, commissionRate, 0, {from: accounts[0]}), 
        "commission cannot be changed more than one in 24h");
    })

    it ("should update validator", async () => {
        const instance = await Validator.deployed();
        const name = web3.utils.fromAscii("");
        let commissionRate = web3.utils.toWei("0.3", "ether");
        await utils.advanceTime(86401);
        await instance.update(name, commissionRate, 0, {from: accounts[0]});
        var commission = await instance.commission.call();
        var expectedRate = commission.rate;
        assert.equal(commissionRate, expectedRate.toString());
    })

    it ("should allocate token", async() => {
        const instance = await Validator.deployed();
        var rewards = web3.utils.toWei("1", "ether");
        await instance.allocateToken(rewards, {from: accounts[0]});

        var inforValidator = await instance.inforValidator({from: accounts[0]});

        var commission = await instance.commission({from: accounts[0]});
        // calculate expected commsission = 1 * rate = rate
        var expectedCommsission = commission.rate.toString()
        assert.equal(inforValidator.accumulatedCommission.toString(), expectedCommsission);
    })
    

    it ("should delegate", async () => {
        const staking = await Staking.deployed()
        const rate = web3.utils.toWei("0.4", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");
        const minSelfDelegation = web3.utils.toWei("0.5", "ether");
        const name = web3.utils.fromAscii("val1");

        await staking.createValidator(name, rate, maxRate, maxChangeRate, minSelfDelegation, {from: accounts[0]})

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)

        await validator.delegate({from: accounts[0], value: web3.utils.toWei("0.4", "ether")})
        const delegation = await validator.delegationByAddr(accounts[0])
        assert.equal(delegation.shares.toString(), web3.utils.toWei("1", "ether"))
        await validator.delegate({from: accounts[1], value: web3.utils.toWei("0.4", "ether")})
        const delegation2 = await validator.delegationByAddr(accounts[1])
        assert.equal(delegation2.shares.toString(), web3.utils.toWei("1", "ether"))
        const valInfo = await validator.inforValidator()
        assert.equal(valInfo.delegationShares, web3.utils.toWei("2", "ether"))
        assert.equal(valInfo.tokens.toString(), web3.utils.toWei("0.8", "ether"))

    })

    it ("should undelegate", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        
        const amount = web3.utils.toWei("0.1", "ether");
        await validator.undelegate(amount, {from: accounts[1]});

        // check delegation
        const delegation =  await validator.delegationByAddr(accounts[1]);

        // check balance remaining
        assert.equal(delegation.shares.toString(), web3.utils.toWei("0.75", "ether"))
        assert.equal(delegation.stake.toString(), web3.utils.toWei("0.3", "ether"))
        
        // check infor undelegate
        var ubdEntries = await validator.ubdEntries(accounts[1], 0, {from: accounts[1]})
        assert.equal(ubdEntries.amount.toString(), amount)
    })

    it ("should not undelegate", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        
        const amount = web3.utils.toWei("0.01", "ether");

        for (var i =0; i < 6; i ++) {
            await validator.undelegate(amount, {from: accounts[1]});
        }

        await utils.assertRevert(validator.undelegate(amount, {from: accounts[1]}), 
        "Returned error: VM Exception while processing transaction: revert too many unbonding delegation entries");

        // not found delgator
        await utils.assertRevert(validator.undelegate(amount, {from: accounts[5]}), 
        "Returned error: VM Exception while processing transaction: revert delegation not found");

    })

    it ("should withdraw", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        await utils.advanceTime(86401 * 8);
        await validator.withdraw({from: accounts[1]})
    })

    it ("should not withdraw", async () => {
        const staking = await Staking.deployed();
        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)

        await utils.assertRevert(validator.withdraw({from: accounts[4]}), 
        "Returned error: VM Exception while processing transaction: revert delegation not found");
    })

    it ("should withdraw commission", async () => {
        const staking = await Staking.deployed();
        const contractAddr = await staking.allVals(0)
        const validator = await Validator.at(contractAddr)
        await validator.delegate({from: accounts[0], value: web3.utils.toWei("0.4", "ether")})
        await finalize([]);
        await validator.withdrawCommission({from: accounts[0]})
    })

    it ("should not withdraw commission", async () => {
        const staking = await Staking.deployed();

        const contractAddr = await staking.allVals(0)
        const validator = await Validator.at(contractAddr)
        await utils.assertRevert(validator.withdrawCommission({from: accounts[0]}), 
        "Returned error: VM Exception while processing transaction: revert no validator commission to reward");
    })

    it("should withdraw delegation rewards", async () => {
        const staking = await Staking.deployed();

        const contractAddr = await staking.allVals(0)
        const validator = await Validator.at(contractAddr)

        await validator.withdrawRewards({from: accounts[0]})
    })

    it("should not withdraw delegation rewards", async () => {
        const staking = await Staking.deployed();

        const contractAddr = await staking.allVals(0)
        const validator = await Validator.at(contractAddr)

        await utils.assertRevert(validator.withdrawRewards({from: accounts[3]}), 
        "Returned error: VM Exception while processing transaction: revert delegator not found");
    })


    it("should slash", () => {

    })

    it("should unjail", () => {

    })

    it("double sign", () => {

    })

    it("validate signature", () => {

    })
})