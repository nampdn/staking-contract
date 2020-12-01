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

    async function createValidator(from) {
        const staking = await Staking.deployed()
        const rate = web3.utils.toWei("0.4", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");
        const minSelfDelegation = web3.utils.toWei("0.5", "ether");
        const name = web3.utils.fromAscii("val1");
        await staking.createValidator(name, rate, maxRate, maxChangeRate, minSelfDelegation, {from})
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
        var update = await instance.update(name, commissionRate, 0, {from: accounts[0]});
        var commission = await instance.commission.call();
        var expectedRate = commission.rate;
        assert.equal(commissionRate, expectedRate.toString());

        // check event
        assert.equal(commissionRate, update.logs[0].args[1].toString());
        assert.equal("0", update.logs[0].args[2].toString());
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
        await createValidator(accounts[0]);
        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)

        await validator.delegate({from: accounts[0], value: web3.utils.toWei("0.4", "ether")})
        await validator.start();
        const delegation = await validator.delegationByAddr(accounts[0])
        assert.equal(delegation.shares.toString(), web3.utils.toWei("1", "ether"))

        var delegate = await validator.delegate({from: accounts[1], value: web3.utils.toWei("0.4", "ether")})
        const delegation2 = await validator.delegationByAddr(accounts[1])
        assert.equal(delegation2.shares.toString(), web3.utils.toWei("1", "ether"))
        const valInfo = await validator.inforValidator()
        assert.equal(valInfo.delegationShares, web3.utils.toWei("2", "ether"))
        assert.equal(valInfo.tokens.toString(), web3.utils.toWei("0.8", "ether"))

        // check event
        assert.equal(accounts[1], delegate.logs[0].args[0]) // check delegator address
        assert.equal(web3.utils.toWei("0.4", "ether"), delegate.logs[0].args[1]) // check delagate amount
    })

    it ("should undelegate", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        
        const amount = web3.utils.toWei("0.1", "ether");
        var undelegate = await validator.undelegate(amount, {from: accounts[1]});

        // check delegation
        const delegation =  await validator.delegationByAddr(accounts[1]);

        // check balance remaining
        assert.equal(delegation.shares.toString(), web3.utils.toWei("0.75", "ether"))
        assert.equal(delegation.stake.toString(), web3.utils.toWei("0.3", "ether"))
        
        // check infor undelegate
        var ubdEntries = await validator.ubdEntries(accounts[1], 0, {from: accounts[1]})
        assert.equal(ubdEntries.amount.toString(), amount)

        // check event
        assert.equal(accounts[1], undelegate.logs[0].args[0])
        assert.equal(amount, undelegate.logs[0].args[1])
    })

    it ("should not undelegate", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        
        await utils.assertRevert(validator.undelegate(web3.utils.toWei("10", "ether"), {from: accounts[1]}), 
        "Returned error: VM Exception while processing transaction: revert not enough delegation shares");

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

    it ("update signer", async () => {
        const staking = await Staking.deployed();
        const valAddr = await staking.allVals(0);
        const validator = await Validator.at(valAddr);
        await validator.updateSigner(accounts[1], {from: accounts[0]});
        const owner = await staking.valOf.call(valAddr);
        const valAddr2 = await staking.ownerOf.call(accounts[1])
        assert.equal(owner, accounts[1]);
        assert.equal(valAddr2, valAddr)
        await validator.updateSigner(accounts[0], {from: accounts[1]});
    })

    it ("should withdraw", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        await utils.advanceTime(86401 * 8);
        
        var withdraw = await validator.withdraw({from: accounts[1]})

        // check event
        assert.equal(accounts[1], withdraw.logs[0].args[0])
    })

    it ("should not withdraw", async () => {
        const staking = await Staking.deployed();
        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)

        await utils.assertRevert(validator.withdraw({from: accounts[4]}), 
        "Returned error: VM Exception while processing transaction: revert delegation not found");

        await utils.assertRevert(validator.withdraw({from: accounts[1]}), 
        "Returned error: VM Exception while processing transaction: revert no unbonding amount to withdraw");
    })

    it ("should withdraw commission", async () => {
        const staking = await Staking.deployed();
        const contractAddr = await staking.allVals(0)
        const validator = await Validator.at(contractAddr)
        await validator.delegate({from: accounts[0], value: web3.utils.toWei("0.4", "ether")})
        await finalize([]);
        var commissionRewards = await validator.getCommissionRewards({from: accounts[0]})

        assert.equal("15854895991882293251", commissionRewards)
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
        var delegationRewards = await validator.getDelegationRewards(accounts[0], {from: accounts[0]})

        assert.equal("18294110759864184520", delegationRewards.toString())
        await validator.withdrawRewards({from: accounts[0]})
    })

    it("should not withdraw delegation rewards", async () => {
        const staking = await Staking.deployed();

        const contractAddr = await staking.allVals(0)
        const validator = await Validator.at(contractAddr)

        await utils.assertRevert(validator.withdrawRewards({from: accounts[3]}), 
        "Returned error: VM Exception while processing transaction: revert delegator not found");
    })


    it("should slash", async () => {
        const staking = await Staking.deployed();
        await createValidator(accounts[5]);
        const val = await Validator.at(await staking.allVals(1));
        
        const amount = web3.utils.toWei("5", "ether");
        await val.delegate({from: accounts[5], value: amount})
        await val.start({from: accounts[5]});
        await finalize([accounts[5]])
    })

    it("should unjail", async () => {
        // @todo should optimize
        // const staking = await Staking.deployed();
        // const val = await Validator.at(await staking.allVals(1));

        // // before jail
        // var inforValidator = await val.inforValidator({from: accounts[5]})
        // assert.equal(inforValidator.jailed, false)

        // // first jail
        // for (var i=0; i<100; i++) {
        //     await staking.mint();
        //     await staking.setPreviousProposer(accounts[0]);
        //     await staking.finalize([accounts[5]], [1000000000000], [false])
        // }

        // // after jail
        // var inforValidator1 = await val.inforValidator({from: accounts[5]})
        // assert.equal(inforValidator1.jailed, true)

        // // unjail
        // await val.unjail({from: accounts[5]})

        // // after unjail
        // var inforValidator3 = await val.inforValidator({from: accounts[5]})
        // assert.equal(inforValidator3.jailed, false)

        // // second jail
        // for (var i=0; i<100; i++) {
        //     await staking.mint();
        //     await staking.setPreviousProposer(accounts[0]);
        //     await staking.finalize([accounts[5]], [1000000000000], [false])
        // }

        // // after second jail 
        // var inforValidator2 = await val.inforValidator({from: accounts[5]})
        // assert.equal(inforValidator2.jailed, true)

        // // second unjail
        // await val.unjail({from: accounts[5]})

        // // after unjail
        // var inforValidator4 = await val.inforValidator({from: accounts[5]})
        // assert.equal(inforValidator4.jailed, false)
    })

    it("double sign", async () => {
        const staking = await Staking.deployed();
        const val = await Validator.at(await staking.allVals(1));

        // before jail
        var inforValidator = await val.inforValidator({from: accounts[5]})
        assert.equal(inforValidator.jailed, false)

        await staking.doubleSign(accounts[5], 1000, 5, {from: accounts[0]});

        const info = await val.inforValidator()
        assert.equal(info.jailed, true)
    })

    it("validate signature", async () => {
        const instance = await Validator.deployed();
    
        var validateSignature =  await instance.validateSignature(1000, false, {from: accounts[0]});
        
        // check event 
        assert.equal("1", validateSignature.logs[0].args[0].toString()) // number of blocks miss
    })

    it ("should withdraw when validator stop", async () => {
        const staking = await Staking.deployed();
        await staking.setMaxValidator(2, {from: accounts[0]})
        const val0 = await Validator.at(await staking.allVals(0));
        await createValidator(accounts[4]);
        const val4 = await Validator.at(await staking.allVals(2));
        await val4.delegate({from: accounts[4], value: web3.utils.toWei("3", "ether")})
        await val4.start({from: accounts[4]});
        
        const amount = web3.utils.toWei("1", "ether");
        await val0.delegate({from: accounts[6], value: amount})
        const val1 = await Validator.at(await staking.allVals(1));
        await val1.delegate({from: accounts[6], value:  web3.utils.toWei("7", "ether")})

        await createValidator(accounts[6]);
        const val6 = await Validator.at(await staking.allVals(3));
        await val6.delegate({from: accounts[6], value:  web3.utils.toWei("0.6", "ether")})

        // reject when the validator is added has an amount smaller than min amount in val set. 
        await utils.assertRevert(val6.start({from: accounts[6]}), "Amount must greater than min amount");

        // val6 is added to valset and val0 is removed
        await val6.delegate({from: accounts[6], value:  web3.utils.toWei("8", "ether")})
        await val6.start({from: accounts[6]});

        // infor validator after the validator is stopped
        var inforVal2 = await val0.inforValidator({from: accounts[0]})
        assert.equal("0",inforVal2.status.toString()) // 0 is unbonding status

        var undelegate1 = await val0.undelegate(web3.utils.toWei("0.1", "ether"), {from: accounts[0]})

        assert.equal(undelegate1.logs[0].event, 'Undelegate')
        assert.equal(undelegate1.logs[0].args[0], accounts[0])
        assert.equal(undelegate1.logs[0].args[1].toString(), web3.utils.toWei("0.1", "ether"))

        // if wait to pass unbond time
        await utils.advanceTime(86401 * 10);

        // undelegate and withdraw 
        var undelegate = await val0.undelegate(web3.utils.toWei("0.6", "ether"), {from: accounts[0]})
        assert.equal(undelegate.logs[0].event, 'Withdraw')
        assert.equal(undelegate.logs[0].args[0], accounts[0])
        assert.equal(undelegate.logs[0].args[1].toString(), web3.utils.toWei("0.6", "ether"))

        // withdraw after undelegate
        var withdraw = await val0.withdraw({from: accounts[0]})
        assert.equal(withdraw.logs[0].event, 'Withdraw')
        assert.equal(withdraw.logs[0].args[0], accounts[0])
        assert.equal(withdraw.logs[0].args[1].toString(), web3.utils.toWei("0.1", "ether"))
    })
})