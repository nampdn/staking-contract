const Staking = artifacts.require("Staking");
const utils = require("./utils");


async function assertRevert(promise) {
    return promise.then(() => {
        throw null;
    }).catch(e => {
        assert.isNotNull(e);
    });
}

contract("Staking", async (accounts) => {
    const powerReduction = Math.pow(10, 6);
    async function finalizeCommit(isSigned) {
        let instance = await Staking.deployed();
        const validatorSet = await getCurrentValidatorSet();
        await instance.mint();
        //await web3.eth.sendTransaction({from: accounts[8], to: instance.address, value: web3.utils.toWei("1000", "ether")})
        await instance.setPreviousProposer(accounts[0]);
        let signed = validatorSet[0].map(_ => true);
        signed[0] = isSigned;
        await instance.finalizeCommit(validatorSet[0], validatorSet[1], signed)
    }

    async function getCurrentValidatorSet() {
        const instance = await Staking.deployed();
        await instance.applyAndReturnValidatorSets({from: accounts[0]});
        return instance.getValidatorSets.call();
    }

    it ("should set root", async() => {
        let instance = await Staking.deployed();
        await instance.setRoot(accounts[0], {from: accounts[0]});
    });

    it ("should not set root", async () => {
        let instance = await Staking.deployed();
        await assertRevert(instance.setRoot(accounts[0], {from: accounts[1]}));
    });

    it ("should set previous proposer", async () => {
        let instance = await Staking.deployed();
        await instance.setPreviousProposer(accounts[0])
    });

    it ("should not set previous proposer", async () => {
        let instance = await Staking.deployed();
        await assertRevert(instance.setPreviousProposer(accounts[0], { from: accounts[1]}));
    });
    

    async function setParams(owner, isOk) {
        const baseProposerReward = web3.utils.toWei("0.1", "ether") // 10%
        const bonusProposerReward = web3.utils.toWei("0.01", "ether") // 1%
        const slashFractionDowntime = web3.utils.toWei("0.1", "ether") // 1%
        const slashFractionDoubleSign = web3.utils.toWei("0.5", "ether") // 1%
        const unBondingTime = 1;
        let instance = await Staking.deployed(); 
        const promise =  instance.setParams(0, 0, 0, baseProposerReward, bonusProposerReward, 
            slashFractionDowntime, unBondingTime, slashFractionDoubleSign, {from: owner})
        if (isOk) {
            await promise;
        } else {
            await assertRevert(promise);
        }
    }


    it ("should set params", async() => {
        await setParams(accounts[0], true);
    });

    it ("should not set params", async() => {
        await setParams(accounts[1]);
    });


    it("should create validator", async () => {
        const instance = await Staking.deployed();
        const maxRate = web3.utils.toWei("0.1", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");

        const bond = web3.utils.toWei("100", "ether")
        await instance.createValidator(0, maxRate, maxChangeRate ,0, {from: accounts[0], value: bond});
        let validatorSet = await getCurrentValidatorSet();
        assert.equal(validatorSet[0][0], accounts[0]);
        assert.equal(validatorSet[1][0].toString(), bond/powerReduction);

        // check delegation
        const delegation = await instance.getDelegation.call(accounts[0], accounts[0]);
        assert.equal(delegation.toString(), web3.utils.toWei("1", "ether"))

        // check validator
        const validator = await instance.getValidator(accounts[0]);
        assert.equal(validator[0].toString(), bond);
        assert.equal(validator[1].toString(), web3.utils.toWei("1", "ether"));
        assert.equal(validator[2], false);
    })

    it ("should not create validator", async() => {
        const instance = await Staking.deployed();
        const bond = web3.utils.toWei("1", "ether")
        const testCases = [
            {
                rate: 0,
                maxRate: 0,
                maxChangeRate: 0,
                minSelfDelegation: 0,
                from: accounts[0],
                message: "validator found"
            }, 
            {
                rate: 0,
                maxRate: web3.utils.toWei("1.1", "ether"),
                maxChangeRate: 0,
                minSelfDelegation: 0,
                from: accounts[5],
                message: "max rate cannot be more than 100%"
            },
            {
                rate: web3.utils.toWei("1", "ether"),
                maxRate: web3.utils.toWei("0.9", "ether"),
                maxChangeRate: 0,
                minSelfDelegation: 0,
                from: accounts[5],
                message: "rate cannot be more than max rate"
            },
            {
                rate: 0,
                maxRate: web3.utils.toWei("0.9", "ether"),
                maxChangeRate: web3.utils.toWei("1", "ether"),
                minSelfDelegation: 0,
                from: accounts[5],
                message: "max change rate cannot be more than max rate"
            },
            {
                rate: 0,
                maxRate: 0,
                maxChangeRate: 0,
                minSelfDelegation:  web3.utils.toWei("2", "ether"),
                from: accounts[5],
                message: "validator's self delegation must be greater than their minimum delegation"
            }
        ];


        for(var testCase of testCases) {
            await assertRevert(instance.createValidator(testCase.rate, testCase.maxRate, testCase.maxChangeRate ,
                testCase.minSelfDelegation, {from: testCase.from, value: bond}));
        }
    })

    it ("should delegate", async() => {
        const instance = await Staking.deployed();
        const bond1to0 = web3.utils.toWei("1", "ether");
        await instance.delegate(accounts[0], {from: accounts[1], value: bond1to0});

        // check delegation
        const delegation = await instance.getDelegation.call(accounts[0], accounts[1]);
        assert.equal(delegation.toString(), web3.utils.toWei("0.01", "ether"))
    });

    it ("should undelegate", async() => {
        const instance = await Staking.deployed();
        const amount = web3.utils.toWei("0.5", "ether");
        await instance.undelegate(accounts[0], amount, {from: accounts[1]});

        // check delegation
        const delegation = await instance.getDelegation.call(accounts[0], accounts[1]);
        assert.equal(delegation.toString(), web3.utils.toWei("0.005", "ether"))

        const udbEntries = await instance.getUBDEntries.call(accounts[0], accounts[1]);
        assert.equal(udbEntries[0][0].toString(), amount);
    })

    it ("should remove delegation", async() => {
        const instance = await Staking.deployed();
        const amount = web3.utils.toWei("0.5", "ether");
        await instance.undelegate(accounts[0], amount, {from: accounts[1]});
        await assertRevert(instance.getDelegation.call(accounts[0], accounts[1]));
    })

    it ("should remove validator", async() => {
        const instance = await Staking.deployed();
        const amount = web3.utils.toWei("100", "ether")
        await instance.undelegate(accounts[0], amount, {from: accounts[0]});
        await assertRevert(instance.getValidator.call(accounts[0]));

        const validatorSets = await getCurrentValidatorSet();
        assert.equal(validatorSets[0].length, 0);
    })

    it ("should not withdraw", async () => {
        const instance = await Staking.deployed();
        await assertRevert(instance.withdraw(accounts[0], {from: accounts[0]}));
    });

    it ("should withdraw", async () => {
        const instance = await Staking.deployed();
        await utils.advanceTime(2000);
        await instance.withdraw(accounts[0], {from: accounts[0]}); 

        await assertRevert(instance.withdraw(accounts[0], {from: accounts[0]}));
    });


    it ("should withdraw delegation rewards", async () => {
        const instance = await Staking.deployed();
        const bond0to0 = web3.utils.toWei("1", "ether");
        const bond1to0 = web3.utils.toWei("1", "ether");
        const bond2to0 = web3.utils.toWei("1", "ether");

        const bond1to1 = web3.utils.toWei("1", "ether");
        const bond2to2 = web3.utils.toWei("1", "ether");

        await instance.createValidator(0, 0,0, 0, {from: accounts[0], value: bond0to0});
        await instance.delegate(accounts[0], {from: accounts[1], value: bond1to0});
        await instance.delegate(accounts[0], {from: accounts[2], value: bond2to0});
        await instance.createValidator(0, 0,0, 0, {from: accounts[1], value: bond1to1});
        await instance.createValidator(0, 0,0, 0, {from: accounts[2], value: bond2to2});

        await finalizeCommit(true);

        let reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("12.569608166231483593", "ether"));
        reward = await instance.getDelegationRewards.call(accounts[0], accounts[1]);
        assert.equal(reward.toString(), web3.utils.toWei("12.569608166231483593", "ether"));
        reward = await instance.getDelegationRewards.call(accounts[0], accounts[2]);
        assert.equal(reward.toString(), web3.utils.toWei("12.569608166231483593", "ether"));

        reward = await instance.getDelegationRewards.call(accounts[1], accounts[1]);
        assert.equal(reward.toString(), web3.utils.toWei("8.872664587928106066", "ether"));

        reward = await instance.getDelegationRewards.call(accounts[2], accounts[2]);
        assert.equal(reward.toString(), web3.utils.toWei("8.872664587928106066", "ether"));


        await instance.withdrawReward(accounts[0], {from: accounts[0]});
        reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
        assert.equal(reward.toString(), web3.utils.toWei("0", "ether"));

        await finalizeCommit(true);

        reward = await instance.getDelegationRewards.call(accounts[2], accounts[2]);
        assert.equal(reward.toString(), web3.utils.toWei("17.745329274261433244", "ether"));

    });

    it ("should withdraw commission rewards", async() => {
        const instance = await Staking.deployed();
        const commissionRate = web3.utils.toWei("0.5", "ether")
        const maxRate = web3.utils.toWei("1", "ether");
        await utils.advanceTime(86401);
        const bond3to3 = web3.utils.toWei("1", "ether");
        await instance.createValidator(commissionRate, maxRate, 0, 0, {from: accounts[3], value: bond3to3});

        await finalizeCommit(true);
        
        let commission = await instance.getValidatorCommission.call(accounts[3]);
        assert.equal(commission.toString(), web3.utils.toWei("3.696943660307728894"));

        const reward = await instance.getDelegationRewards.call(accounts[3], accounts[3]);
        assert.equal(reward.toString(), web3.utils.toWei("3.696943660307728895", "ether"));

        await instance.withdrawValidatorCommission({from: accounts[3]});

        commission = await instance.getValidatorCommission.call(accounts[3]);
        assert.equal(commission.toString(), web3.utils.toWei("0"));

    });


    // it("should delegate to validator", async () => {
    //     let instance = await Staking.deployed();
    //     const bond = web3.utils.toWei("0.1", "ether")
    //     await instance.delegate(accounts[0], {from:accounts[1], value: bond})

    //     let validatorSet = await getCurrentValidatorSet();
    //     assert.equal(validatorSet[0][0], accounts[1]);

    //     const bond2 = web3.utils.toWei("99.9", "ether")
    //     await instance.delegate(accounts[0], {from:accounts[1], value: bond2})
    //     validatorSet = await getCurrentValidatorSet();
    //     assert.equal(validatorSet[0][0], accounts[0]);
    //     assert.equal(validatorSet[1][0], web3.utils.toWei("200", "ether")/powerReduction);

    //     const stake = await instance.getDelegationStake.call(accounts[1], accounts[0]);
    //     assert.equal(stake.toString(), web3.utils.toWei("100", "ether"));
    // })

    // it("should withdrawl delegation reward", async () => {
    //     // // feeCollected = 7% * 5000000000/6311520 = 55,454153675
    //     // rewards:
    //     // pr: 55,454153675 *  (10+ 1)% = 6,099956904
    //     // v1r: 55,454153675 * 89% * (200/(200 + 101 + 1)) = 32,684898524 + 6,099956904 = 38,784855428
    //     //    - del1: 88,139052199/2 = 19,392427714


    //     let instance = await Staking.deployed();
    //     let reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
    //     assert.equal(reward, 0);

    //     await finalizeCommit(true)
    //     await finalizeCommit(true)

    //     const feeCollected = await instance.getBlockProvision.call();
    //     assert.equal(feeCollected.toString(), web3.utils.toWei("55.454153674550662914", "ether"))


    //     reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
    //     assert.equal(reward.toString(), web3.utils.toWei("19.392427713805614200", "ether"));

    //     await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});


    //     reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
    //     assert.equal(reward.toString(), "0");

    //     await finalizeCommit(true)

    //     reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
    //     assert.equal(reward.toString(), web3.utils.toWei("19.392427789018864700", "ether"));

        
    //     reward = await instance.getDelegationRewards.call(accounts[1], accounts[0]);
    //     assert.equal(reward.toString(), web3.utils.toWei("38.784855502824478900", "ether"));

        
    // })
    
    // it("should withdrawl commission rewards", async() => {
    //     const instance = await Staking.deployed();
    //     await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});
    //     await utils.advanceTime(86402);
    //     // newcommission rate: 1%
    //     await instance.updateValidator(web3.utils.toWei("0.01", "ether"), 0, "", "", "", "")

    //     await finalizeCommit(true)

    //     reward = await instance.getValidatorCommissionReward.call(accounts[0]);
    //     assert.equal(reward.toString(), web3.utils.toWei("0.387848557284642311", "ether"));

    //     await instance.withdrawValidatorCommissionReward({from: accounts[0]});

    //     reward = await instance.getValidatorCommissionReward.call(accounts[0]);
    //     assert.equal(reward.toString(), "0");

    //     reward = await instance.getDelegationRewards.call(accounts[0], accounts[0]);
    //     assert.equal(reward.toString(), web3.utils.toWei("19.198503585589794400", "ether"));

    // })

    // it("should undelegate", async () => {
    //     const instance = await Staking.deployed();
    //     const boud3to0 = web3.utils.toWei("100", "ether");
    //     await instance.delegate(accounts[0], {from: accounts[3], value: boud3to0})

    //     let stake = await instance.getDelegationStake.call(accounts[3], accounts[0])
    //     assert.equal(stake.toString(), boud3to0);

    //     await instance.undelegate(accounts[0], String(boud3to0/2), {from: accounts[3]});

    //     stake = await instance.getDelegationStake.call(accounts[3], accounts[0])
    //     assert.equal(stake.toString(), boud3to0/2);

    //     await instance.undelegate(accounts[0], String(boud3to0/2), {from: accounts[3]});
    //     stake = await instance.getDelegationStake.call(accounts[3], accounts[0])
    //     assert.equal(stake.toString(), "0");

    //     reward = await instance.getDelegationRewards.call(accounts[3], accounts[0]);
    //     assert.equal(reward.toString(), web3.utils.toWei("0", "ether"));
    // })

    // it("should withdraw", async() => {
    //     const instance = await Staking.deployed();

    //     let udb = await instance.getUnboudingDelegation.call(accounts[3], accounts[0])
    //     assert.equal(udb[0], 0)
    //     assert.equal(udb[1].toString(), web3.utils.toWei("100", "ether"))

    //     await utils.advanceTime(2000);
    //     await finalizeCommit(true);
    //     udb = await instance.getUnboudingDelegation.call(accounts[3], accounts[0])
    //     assert.equal(udb[0].toString(), web3.utils.toWei("100", "ether"))
    //     assert.equal(udb[1].toString(), web3.utils.toWei("100", "ether"))

    //     await instance.withdraw(accounts[0], {from: accounts[3]});
    //     udb = await instance.getUnboudingDelegation.call(accounts[3], accounts[0])
    //     assert.equal(udb[0], 0)
    //     assert.equal(udb[1], 0)
    // })

    // it ("should jail validator", async() => {
    //     const instance = await Staking.deployed();
    //     // update maxMissed block
    //     await instance.setParams(0, 2, 1, 0,0, 0, 0, 0);
    //     await finalizeCommit(false);

    //     let val = await instance.getValidator.call(accounts[0]);
    //     assert.equal(val[1], false);

    //     await finalizeCommit(false);
    //     val = await instance.getValidator.call(accounts[0]);
    //     assert.equal(val[1], true);


    //     stake = await instance.getDelegationStake.call(accounts[0], accounts[0]);
    //     assert.equal(stake.toString(), web3.utils.toWei("90", "ether"));
        
    //     let validatorSet = await getCurrentValidatorSet();
    //     assert.equal(validatorSet[0].length, 2);


    // });

    // it("should unjail validator", async () => {
    //     const instance = await Staking.deployed();

    //     let validatorSet = await getCurrentValidatorSet();
    //     assert.equal(validatorSet[0][0], accounts[1]);

    //     await utils.advanceTime(2000);
    //     await instance.unjail({from: accounts[0]});
    //     val = await instance.getValidator.call(accounts[0]);
    //     assert.equal(val[1], false);
    //     assert.equal(val[0].toString(), web3.utils.toWei("180", "ether"));

    //     validatorSet = await getCurrentValidatorSet();
    //     assert.equal(validatorSet[0][0], accounts[0]);
    // })

    // it ("should check delegation reward after unjail", async () => {
    //     // feeCollected = 7% * 5000000000/6311520 = 55,454153675
    //     // rewards:
    //     // pr: 55,454153675 *  (10 + 1)% = 6,099956904
    //     // v1r: 55,454153675 * 89% * (180/(180 + 101 + 1)) = 31,50267879 + 6,099956904 = 37,602635694 - 37,602635694 * 1% = 37,226609337
    //     //    - del1: 37,226609337/2 = 18,613304669
    //     //    - del2 = del1
    //     // c2r: 55,454153675 * 89% * (101/(180 + 101 + 1)) = 17,676503099
    //     // c3r: 55,454153675 * 89% * (1/(180 + 101 + 1)) = 0,175014882

    //     const instance = await Staking.deployed();
    //     await instance.withdrawValidatorCommissionReward({ from: accounts[0]})
    //     await instance.withdrawDelegationReward(accounts[0], {from: accounts[0]});
    //     await instance.withdrawDelegationReward(accounts[0], {from: accounts[1]});
    //     await instance.withdrawDelegationReward(accounts[1], {from: accounts[1]});
    //     await instance.withdrawDelegationReward(accounts[2], {from: accounts[2]});

    //     await finalizeCommit(true);

    //     // v1:d1
    //     let reward = await instance.getDelegationRewards.call(accounts[0], accounts[0])
    //     assert.equal(reward.toString(), web3.utils.toWei("18.613305803860606710", "ether"));

    //     // v1:d2
    //     reward = await instance.getDelegationRewards.call(accounts[1], accounts[0])
    //     assert.equal(reward.toString(), web3.utils.toWei("18.613305803860606710", "ether"));

    //     // val 1
    //     let commission = await instance.getValidatorCommissionReward.call(accounts[0]);
    //     assert.equal(commission.toString(), web3.utils.toWei("0.376026379875971852", "ether"));

    //     // v2:d1
    //     reward = await instance.getDelegationRewards.call(accounts[1], accounts[1])
    //     assert.equal(reward.toString(), web3.utils.toWei("17.676504176891072973", "ether"));

    //     // v3:d1
    //     reward = await instance.getDelegationRewards.call(accounts[2], accounts[2])
    //     assert.equal(reward.toString(), web3.utils.toWei("0.175014892840505632", "ether"));

    // })

    // it("should check doubleSign", async () => {
    //     const instance = await Staking.deployed();
    //     const boud4to0 = web3.utils.toWei("10", "ether");
    //     await instance.delegate(accounts[0], {from:accounts[4], value: boud4to0})
    //     await instance.doubleSign(accounts[0], 1000); 
    //     let stake = await instance.getDelegationStake.call(accounts[4], accounts[0]);
    //     assert.equal(stake.toString(), String(boud4to0/2));

    //     await utils.advanceTime(2000);
    //     await instance.unjail({from: accounts[0]});
    // })

    // it("should check slash unbounding delegation entries", async () => {
    //     const instance = await Staking.deployed();
    //     await instance.undelegate(accounts[0], web3.utils.toWei("5", "ether"), {from : accounts[4]});
    //     await instance.doubleSign(accounts[0], 1000); 
    //     const udb = await instance.getUnboudingDelegation.call(accounts[4], accounts[0])
    //     assert.equal(udb[1].toString(), web3.utils.toWei("2.5", "ether"))
    // })

    // it("should check delete delegation and validator when all undelgation is completed", async() => {
    //     const instance = await Staking.deployed();
    //     const boud = web3.utils.toWei("1", "ether")
    //     await instance.createValidator(0,0, 0,0, "val1", "val.com", "val1@gmail.com", "val1", {from: accounts[6], value: boud});
    //     await instance.undelegate(accounts[6], boud, {from : accounts[6]});
    //     await utils.advanceTime(2000);
    //     await instance.withdraw(accounts[6], {from: accounts[6]});

    //     await instance.createValidator(0,0, 0,0, "val1", "val.com", "val1@gmail.com", "val1", {from: accounts[6], value: boud});
    // });
})