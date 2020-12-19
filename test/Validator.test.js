const Validator = artifacts.require("Validator");
const Staking = artifacts.require("Staking");
const Minter = artifacts.require("Minter");
const Params = artifacts.require("Params");
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
        const name = web3.utils.fromAscii("val1");
        await staking.createValidator(name, rate, maxRate, maxChangeRate, {from});
        const val = await Validator.at(await staking.ownerOf(from));
        return val;
    }

    
    it("should create validator", async () => {
        const instance = await Validator.deployed();

        const rate = web3.utils.toWei("0.1", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.2", "ether");
        const name = web3.utils.fromAscii("val1");
        await instance.initialize(name, accounts[0], rate, maxRate, maxChangeRate, {from: accounts[0]});

        var inforValidator = await instance.inforValidator({from: accounts[0]});
        var commission = await instance.commission({from: accounts[0]});

        var expectedName = inforValidator.name;
        var expectedRate = commission.rate;
        var expectedMaxRate = commission.maxRate;
        var expectedMaxChangeRate = commission.maxChangeRate;

        assert.equal("val1", web3.utils.toAscii(expectedName).toString().replace(/\0/g, ''));
        assert.equal(rate, expectedRate.toString());
        assert.equal(maxRate, expectedMaxRate.toString());
        assert.equal(maxChangeRate, expectedMaxChangeRate.toString());
    })

    it ("should not update validator", async () => {
        const instance = await Validator.deployed();
        const name = web3.utils.fromAscii("111111111111111");
        commissionRate = web3.utils.toWei("2", "ether");
        await utils.assertRevert(instance.updateCommissionRate(commissionRate, {from: accounts[0]}), 
        "commission cannot be changed more than one in 24h");

        await utils.advanceTime(86400);

        commissionRate = web3.utils.toWei("0.4", "ether");
        await utils.assertRevert(instance.updateCommissionRate(commissionRate, {from: accounts[0]}), 
        "commission cannot be changed more than max change rate");

        commissionRate = web3.utils.toWei("2", "ether");
        await utils.assertRevert(instance.updateCommissionRate(commissionRate, {from: accounts[0]}), 
        "commission cannot be more than the max rate");

    })

    it ("should update validator", async () => {
        const instance = await Validator.deployed();
        const name = web3.utils.fromAscii("12131");
        let commissionRate = web3.utils.toWei("0.3", "ether");
        await utils.advanceTime(86401);
        var update = await instance.updateCommissionRate(commissionRate, {from: accounts[0]});
        var commission = await instance.commission.call();
        var expectedRate = commission.rate;
        assert.equal(commissionRate, expectedRate.toString());

        // check event
        assert.equal(commissionRate, update.logs[0].args[0].toString());
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
        const validator =  await createValidator(accounts[0]);
        const valAddr = await staking.allVals(0)

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
        assert.equal(valInfo.tokens.toString(), await staking.balanceOf(valAddr))
        assert.equal(await staking.totalBonded(), valInfo.tokens.toString())

        // check event
        assert.equal(accounts[1], delegate.logs[0].args[0]) // check delegator address
        assert.equal(web3.utils.toWei("0.4", "ether"), delegate.logs[0].args[1]) // check delagate amount
        
    })

    it ("should undelegate", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        
        // undelegate with stake remaining greater than the min stake amount
        const amount = web3.utils.toWei("0.1", "ether");
        var undelegate = await validator.undelegateWithAmount(amount, {from: accounts[1]});

        // check delegation
        var delegation =  await validator.delegationByAddr(accounts[1]);

        // check balance remaining
        assert.equal(delegation.shares.toString(), web3.utils.toWei("0.75", "ether"))
        assert.equal(delegation.stake.toString(), web3.utils.toWei("0.3", "ether"))

        // undelegate all stake amount
        await validator.undelegateWithAmount(web3.utils.toWei("0.3", "ether"), {from: accounts[1]});
        var delegation2 =  await validator.delegationByAddr(accounts[1]);
        // check balance remaining
        assert.equal(delegation2.shares.toString(), "0")
        assert.equal(delegation2.stake.toString(), "0")

        // check infor undelegate
        var ubdEntries = await validator.ubdEntries(accounts[1], 0, {from: accounts[1]})
        assert.equal(ubdEntries.amount.toString(), amount)

        // check event
        assert.equal(accounts[1], undelegate.logs[0].args[0])
        assert.equal(amount, undelegate.logs[0].args[1])

        const valInfo = await validator.inforValidator()
        assert.equal(valInfo.tokens.toString(), web3.utils.toWei("0.4", "ether"))
        assert.equal(valInfo.tokens.toString(), await staking.balanceOf(valAddr))
        assert.equal(await staking.totalBonded(), valInfo.tokens.toString())

    })

    it ("should not undelegate", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        let tx = await validator.delegate({from: accounts[1], value: web3.utils.toWei("0.7", "ether")});

        await utils.assertRevert(validator.undelegateWithAmount(web3.utils.toWei("0.6999", "ether"), {from: accounts[1]}), "Undelegate amount invalid");
        
        await utils.assertRevert(validator.undelegateWithAmount(web3.utils.toWei("10", "ether"), {from: accounts[1]}), "SafeMath: subtraction overflow");

        const amount = web3.utils.toWei("0.01", "ether");
        for (var i =0; i < 5; i ++) {
            await validator.undelegateWithAmount(amount, {from: accounts[1]});
        }

        await utils.assertRevert(validator.undelegateWithAmount(amount, {from: accounts[1]}), "too many unbonding delegation entries");

        // not found delgator
        await utils.assertRevert(validator.undelegateWithAmount(amount, {from: accounts[5]}), "delegation not found"); // 'delegation not found
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

    it ("should not update signer", async () => {
        const staking = await Staking.deployed();
        const valAddr = await staking.allVals(0);
        const validator = await Validator.at(valAddr);
        await utils.assertRevert(validator.updateSigner(accounts[1], {from: accounts[2]}), "Ownable: caller is not the validator");
    })

    it ("should withdraw", async () => {
        const staking = await Staking.deployed();

        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        await utils.advanceTime(1814401);
        var withdraw = await validator.withdraw({from: accounts[1]})
        // check event
        assert.equal(accounts[1], withdraw.logs[0].args[0])
    })

    it ("should not withdraw", async () => {
        const staking = await Staking.deployed();
        const valAddr = await staking.allVals(0)
        const validator = await Validator.at(valAddr)
        await utils.assertRevert(validator.withdraw({from: accounts[4]}), "delegation not found");
        await utils.assertRevert(validator.withdraw({from: accounts[1]}),"no unbonding amount to withdraw");
    })

    it ("should withdraw commission", async () => {
        const staking = await Staking.deployed();
        const contractAddr = await staking.allVals(0)
        const validator = await Validator.at(contractAddr)
        await validator.delegate({from: accounts[0], value: web3.utils.toWei("0.4", "ether")})
        await finalize([]);
        var commissionRewards = await validator.getCommissionRewards({from: accounts[0]})

        assert.equal("3170979198376458649", commissionRewards.toString())
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

        assert.equal("2624258646932241641", delegationRewards.toString())
        const tx = await validator.withdrawRewards({from: accounts[0]})
    })

    it("should not withdraw delegation rewards", async () => {
        const staking = await Staking.deployed();

        const contractAddr = await staking.allVals(0)
        const validator = await Validator.at(contractAddr)

        await utils.assertRevert(validator.withdrawRewards({from: accounts[3]}), "delegation not found");
    })

    it("should unjail", async () => {
        const staking = await Staking.deployed();
        await staking.setValidatorParams(600, web3.utils.toWei("0.0001", "ether"), 
        1814400, web3.utils.toWei("0.05", "ether"), 2,  web3.utils.toWei("0.5", "ether"), 
        web3.utils.toWei("0.01", "ether"), web3.utils.toWei("0.1", "ether"), web3.utils.toWei("0.1", "ether"));

        await createValidator(accounts[5]);
        const val = await Validator.at(await staking.allVals(1));
        const amount = web3.utils.toWei("5", "ether");
        await val.delegate({from: accounts[5], value: amount})
        await val.start({from: accounts[5]});

        // before jail
        info = await val.inforValidator.call();
        assert.equal(info.jailed, false)

        // first jail
        await finalize([accounts[5]]);
        let missedBlock = await val.getMissedBlock.call();
        assert.equal(missedBlock[0], true);
        await finalize([accounts[5]]);
        missedBlock = await val.getMissedBlock.call();
        assert.equal(missedBlock[0], false);
        // after jail
        info = await val.inforValidator.call();
        assert.equal(info.jailed, true)
        // downtime slashed: 5 - 5 * 0,01% = 4.9995
        assert.equal(info.tokens.toString(), web3.utils.toWei("4.9995", "ether"))
        
        // unjail
        await utils.advanceTime(601);
        await val.unjail({from: accounts[5]});
        await val.start({from: accounts[5]});

        // after unjail
        info = await val.inforValidator.call();
        assert.equal(info.jailed, false)
    })

    it("double sign", async () => {
        const staking = await Staking.deployed();
        const valAddr = await await staking.allVals(1)
        const val = await Validator.at(valAddr);

        let valSet = await staking.getValidatorSets()
        assert.equal(valSet[0][1], await staking.valOf(valAddr))

        // before jail
        var inforValidator = await val.inforValidator({from: accounts[5]})
        assert.equal(inforValidator.jailed, false)
        await val.undelegateWithAmount(web3.utils.toWei("1", "ether"), {from: accounts[5]})
        await staking.doubleSign(accounts[5], valSet[1][1], 1, {from: accounts[0]});

        var totalSlashedToken = await staking.totalSlashedToken()
        assert.equal(web3.utils.toWei("0.200475000000000001", "ether"), totalSlashedToken.toString())

        var slashEventLength = await val.getSlashEventsLength()
        assert.equal(slashEventLength.toString(), "2")

        const info = await val.inforValidator()
        assert.equal(info.jailed, true)

        valSet = await staking.getValidatorSets()
        assert.equal(valSet[0].length, 1);
        assert.equal(info.tokens.toString(), web3.utils.toWei('3.799525000000000000', "ether"))

        const ubdEntries = await val.getUBDEntries.call(accounts[5])
        assert.equal(ubdEntries[0][0].toString(), web3.utils.toWei("0.95", "ether"))
    })

    it ("Should not update max validator", async () => {
        const staking = await Staking.deployed();

        await createValidator(accounts[8]);
        const val8 = await Validator.at(await staking.allVals(2));
        const amount8 = web3.utils.toWei("0.1", "ether");
        await val8.delegate({from: accounts[8], value: amount8})
        await val8.start({from: accounts[8]});

        // proposal max validator
        await staking.proposalMaxProposers(2, {from: accounts[0]})
        var proposal = await staking.proposal() 
        assert.equal(proposal.toString(), 2)
        await utils.assertRevert(staking.addVote({from: accounts[3]}), "Not the proposer");
        await staking.addVote({from: accounts[8]})
        await utils.assertRevert(staking.addVote({from: accounts[8]}), "Vote only once");
        await utils.assertRevert(staking.setMaxProposers(2, {from: accounts[0]}), "Insufficient voting power");
    })

    it ("Should update max validator", async () => {
        const staking = await Staking.deployed();

        // befor update
        const params = await Params.at(await staking.params())
        var maxValidator = await params.getMaxProposers()
        assert.equal(maxValidator.toString(), "20")
        await staking.addVote({from: accounts[0]})
        var voted = await staking.vote(accounts[0])
        assert.equal(voted, true)
        await staking.setMaxProposers(2, {from: accounts[0]})

        // after update
        var maxValidator1 = await params.getMaxProposers()
        assert.equal(maxValidator1.toString(), "2")

        // make sure reset
        var voted1 = await staking.vote(accounts[0])
        assert.equal(voted1, false)
        var vote2 = await staking.vote(accounts[8])
        assert.equal(vote2, false)
        var totalVote = await staking.totalVoted()
        assert.equal(totalVote.toString(), "0")
    })

    it ("should withdraw when validator stop", async () => {
        const staking = await Staking.deployed();
        const val0 = await Validator.at(await staking.allVals(0));

        await createValidator(accounts[4]);
        const val4 = await Validator.at(await staking.allVals(3));
        await val4.delegate({from: accounts[4], value: web3.utils.toWei("3", "ether")})
        await val4.start({from: accounts[4]});
        
        const amount = web3.utils.toWei("1", "ether");
        await val0.delegate({from: accounts[6], value: amount})
        const val1 = await Validator.at(await staking.allVals(1));
        await val1.delegate({from: accounts[6], value:  web3.utils.toWei("7", "ether")})

        await createValidator(accounts[6]);
        const val6 = await Validator.at(await staking.allVals(4));
        await val6.delegate({from: accounts[6], value:  web3.utils.toWei("0.6", "ether")})

        // reject when the validator is added has an amount smaller than min amount in val set. 
        await utils.assertRevert(val6.start({from: accounts[6]}), "Amount must greater than min amount");

        // val6 is added to valset and val0 is removed
        await val6.delegate({from: accounts[6], value:  web3.utils.toWei("8", "ether")})
        await val6.start({from: accounts[6]});

        // infor validator after the validator is stopped
        var inforVal2 = await val0.inforValidator({from: accounts[0]})
        assert.equal("0",inforVal2.status.toString()) // 0 is unbonding status

        var undelegate1 = await val0.undelegateWithAmount(web3.utils.toWei("0.1", "ether"), {from: accounts[0]})

        assert.equal(undelegate1.logs[0].event, 'Undelegate')
        assert.equal(undelegate1.logs[0].args[0], accounts[0])
        assert.equal(undelegate1.logs[0].args[1].toString(), web3.utils.toWei("0.1", "ether"))

        // if wait to pass unbond time
        await utils.advanceTime(1814402);

        // undelegate and withdraw 
        var undelegate = await val0.undelegateWithAmount(web3.utils.toWei("0.6", "ether"), {from: accounts[0]})
        assert.equal(undelegate.logs[0].event, 'Withdraw')
        assert.equal(undelegate.logs[0].args[0], accounts[0])
        assert.equal(undelegate.logs[0].args[1].toString(), web3.utils.toWei("0.6", "ether"))

        // withdraw after undelegate
        var withdraw = await val0.withdraw({from: accounts[0]})
        assert.equal(withdraw.logs[0].event, 'Withdraw')
        assert.equal(withdraw.logs[0].args[0], accounts[0])
        assert.equal(withdraw.logs[0].args[1].toString(), web3.utils.toWei("0.1", "ether"))
    })

    it ("should undelegate all stake", async () => {
        const staking = await Staking.deployed();

        const val = await Validator.at(await staking.allVals(1));
        await val.delegate({from: accounts[4], value: web3.utils.toWei("3.000000000000000003", "ether")})

        // check infor delegate 
        var delegation =  await val.delegationByAddr(accounts[4]);
        assert.equal(web3.utils.toWei("2.999999999999999999", "ether"), delegation.stake.toString())
     
        var undelegate = await val.undelegate({from: accounts[4]});
        assert.equal(undelegate.logs[0].event, 'Withdraw')
        assert.equal(undelegate.logs[0].args[0], accounts[4])

        // make sure delegator is deleted 
        await utils.assertRevert(val.undelegate({from: accounts[4]}), "delegation not found")

        // undelegate 
        await val.delegate({from: accounts[7], value: web3.utils.toWei("10", "ether")})
        var delegation1 =  await val.delegationByAddr(accounts[7]);
        var stakeAmount = await delegation1.stake.toString()
        await val.undelegateWithAmount(stakeAmount, {from: accounts[7]})

        // make sure delegator is deleted 
        await utils.assertRevert(val.undelegate({from: accounts[7]}), "delegation not found")
    })

    it ("should not start validator with balance smaller than min validator balance", async () => {
        const staking = await Staking.deployed();
        await createValidator(accounts[9]);
        const val9 = await Validator.at(await staking.allVals(5));
        await val9.delegate({from: accounts[9], value:  web3.utils.toWei("0.015", "ether")})

        await utils.assertRevert(val9.start({from: accounts[9]}), "Address balance must greater or equal minimum validator balance")

        await val9.delegate({from: accounts[9], value:  web3.utils.toWei("10", "ether")})
        await val9.start({from: accounts[9]})

        // before undelegate
        var inforVal = await val9.inforValidator({from: accounts[9]})
        assert.equal(inforVal.status.toString(), "2") // bonded
        await val9.undelegateWithAmount(web3.utils.toWei("10", "ether"), {from: accounts[9]})
        await utils.advanceTime(1814402);

        await val9.withdraw({from: accounts[9]})
        // after undelegate
        var inforVal1 = await val9.inforValidator({from: accounts[9]})
        assert.equal(inforVal1.status.toString(), "0") // unbonding
    })

    it ("should delete delegation", async () => {
        const staking = await Staking.deployed();
        const val9 = await Validator.at(await staking.allVals(5));
     
        await val9.undelegateWithAmount(web3.utils.toWei("0.015", "ether"), {from: accounts[9]})
        await utils.assertRevert(val9.undelegate({from: accounts[9]}), "delegation not found")
    })

    it ("should get delegation", async () => {
        const staking = await Staking.deployed();

        const val = await Validator.at(await staking.allVals(1));

        var delegation = await val.getDelegations({from: accounts[5]})
        assert.equal("2", delegation[0].length)
    })
    
    it("should update name", async () => {
        const staking = await Staking.deployed();
        const val4 = await Validator.at(await staking.allVals(3));
        const name = web3.utils.fromAscii("test");
        await val4.updateName(name, {from: accounts[4], value: web3.utils.toWei("2", "ether")})
        await utils.assertRevert(val4.updateName(name, {from: accounts[4], value: web3.utils.toWei("0.001", "ether")}), "Min amount is 10000 KAI")
    })
})