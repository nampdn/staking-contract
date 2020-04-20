const Staking = artifacts.require("Staking");
const utils = require("./utils");


async function assertRevert(promise, includeStr = "") {
    return promise.then(() => {
        throw null;
    }).catch(e => {
        assert.isNotNull(e);
        if (includeStr != "" && e != null) {
            assert.include(e.message, includeStr);
        }
    });
}

async function setParams(owner, isOk) {
    const baseProposerReward = web3.utils.toWei("0.1", "ether") // 10%
    const bonusProposerReward = web3.utils.toWei("0.01", "ether") // 1%
    const slashFractionDowntime = web3.utils.toWei("0.1", "ether") // 1%
    const slashFractionDoubleSign = web3.utils.toWei("0.5", "ether") // 50%
    const unBondingTime = 1;
    const signedBlockWindow= 2;
    const minSignedBlockPerWindow = web3.utils.toWei("0.5", "ether")
    let instance = await Staking.deployed(); 
    const promise =  instance.setParams(0, 0, baseProposerReward, bonusProposerReward, 
        slashFractionDowntime, unBondingTime, slashFractionDoubleSign, signedBlockWindow, minSignedBlockPerWindow, {from: owner})
    if (isOk) {
        await promise;
    } else {
        await assertRevert(promise, "permission denied");
    }
}

contract("Staking", async (accounts) => {
    const powerReduction = Math.pow(10, 6);
    async function finalizeCommit(notSigned) {
        notSigned = notSigned  || [];
        let instance = await Staking.deployed();
        const validatorSet = await getCurrentValidatorSet();
        await instance.mint();
        //await web3.eth.sendTransaction({from: accounts[8], to: instance.address, value: web3.utils.toWei("1000", "ether")})
        await instance.setPreviousProposer(accounts[0]);
        let signed = validatorSet[0].map(addr => notSigned.indexOf(addr) === -1);
        await instance.finalizeCommit(validatorSet[0], validatorSet[1], signed)
    }

    async function getCurrentValidatorSet() {
        const instance = await Staking.deployed();
        await instance.applyAndReturnValidatorSets({from: accounts[0]});
        return instance.getValidatorSets.call();
    }

    async function mint(num) {
        const instance = await Staking.deployed();
        for (var i =0; i < num; i ++) {
            await instance.mint();
        }
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


    it ("should set params", async() => {
        await setParams(accounts[0], true);
    });

    it ("should not set params", async() => {
        await setParams(accounts[1]);
    });

    it ("should not finalize", async () => {
        const instance = await Staking.deployed();
        await assertRevert(instance.finalizeCommit([], [], [], {from: accounts[1]}), "permission denied");
    });


    it ("should set total bonded", async () => {
        const instance = await Staking.deployed();
        await instance.setTotalBonded(web3.utils.toWei("5000000000", "ether"));
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

    it ("should not delegate", async () => {
        const instance = await Staking.deployed();
        const bond1to0 = web3.utils.toWei("1", "ether");
        
        // validator not found
        await assertRevert(instance.delegate(accounts[5], {from: accounts[1], value: bond1to0}));

        // invalid delegation amount
        await assertRevert(instance.delegate(accounts[0], {from: accounts[1], value: 0}));

    });

    it ("should delegate", async() => {
        const instance = await Staking.deployed();
        const bond1to0 = web3.utils.toWei("1", "ether");
        await instance.delegate(accounts[0], {from: accounts[1], value: bond1to0});

        // check delegation
        const delegation = await instance.getDelegation.call(accounts[0], accounts[1]);
        assert.equal(delegation.toString(), web3.utils.toWei("0.01", "ether"))
    });

    it ("should not undelegate", async () => {
        const instance = await Staking.deployed();
        const amount = web3.utils.toWei("1.5", "ether");

        // delegation not found
        await assertRevert(instance.undelegate(accounts[0], {from: accounts[5]} ))

        // invalid undelegate amount
        await assertRevert(instance.undelegate(accounts[0], amount, {from: accounts[1]}));
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

        await utils.advanceTime(2000);
        await instance.withdraw(accounts[0], {from: accounts[1]});
    })

    it ("should remove validator", async() => {
        const instance = await Staking.deployed();
        const amount = web3.utils.toWei("100", "ether");
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

        await finalizeCommit([]);

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

        await finalizeCommit([]);

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

        await finalizeCommit([]);
        
        let commission = await instance.getValidatorCommission.call(accounts[3]);
        assert.equal(commission.toString(), web3.utils.toWei("3.696943660307728894"));

        const reward = await instance.getDelegationRewards.call(accounts[3], accounts[3]);
        assert.equal(reward.toString(), web3.utils.toWei("3.696943660307728895", "ether"));

        await instance.withdrawValidatorCommission({from: accounts[3]});

        commission = await instance.getValidatorCommission.call(accounts[3]);
        assert.equal(commission.toString(), web3.utils.toWei("0"));

    });


    it("should slash", async () => {
        const instance = await Staking.deployed();
        const bond4to4 = web3.utils.toWei("1", "ether");
        await instance.createValidator(0, 0, 0, 0, {from: accounts[4], value: bond4to4});
        await instance.doubleSign(accounts[4], 1000000000000, 10);

        const validator = await instance.getValidator.call(accounts[4]);
        assert.equal(validator[0].toString(), web3.utils.toWei("0.5", "ether"));
    });

    it("should slash unbonding delegation entries", async () => {
        const instance = await Staking.deployed();
        const bond5to5 = web3.utils.toWei("1", "ether");
        await instance.createValidator(0, 0, 0, 0, {from: accounts[5], value: bond5to5});

        const amount = web3.utils.toWei("0.1", "ether")
        await instance.undelegate(accounts[5], amount, {from: accounts[5]});
        await instance.doubleSign(accounts[5], 1000000000000, 10);

        const udbEntries = await instance.getUBDEntries.call(accounts[5], accounts[5]);
        assert.equal(udbEntries[0][0].toString(), amount/2);

        const validator = await instance.getValidator.call(accounts[5]);
        assert.equal(validator[0].toString(), web3.utils.toWei("0.45", "ether"));

    });

    it ("should slash delegation rewards", async () => {
        const instance = await Staking.deployed();
        const bond6to6 = web3.utils.toWei("1", "ether");
        await instance.createValidator(0, 0, 0, 0, {from: accounts[6], value: bond6to6});
        await finalizeCommit([accounts[6]]);
        await finalizeCommit([accounts[6]]);
        await finalizeCommit([accounts[6]]);
        await utils.advanceTime(601);
        await instance.unjail({from: accounts[6]});
        await finalizeCommit([]);
        let rewards = await instance.getDelegationRewards.call(accounts[6], accounts[6]);
        assert.equal(rewards.toString(), web3.utils.toWei("12.237310357231678083"));

    });


    it ("should not unjail", async() => {
        const instance = await Staking.deployed();

        // validator not found
        await assertRevert(instance.unjail({from: accounts[7]}));

        const bond6to6 = web3.utils.toWei("1", "ether");
        const minSelfDelegation = web3.utils.toWei("0.9", "ether");
        await instance.createValidator(0, 0, 0, minSelfDelegation, {from: accounts[7], value: bond6to6});

        // validator not jailed
        await assertRevert(instance.unjail({from: accounts[7]}));

        // slash and jail
        await finalizeCommit([accounts[7]]);
        await finalizeCommit([accounts[7]]);
        await finalizeCommit([accounts[7]]);

        const validator = await instance.getValidator.call(accounts[7]);
        assert.equal(validator[2], true);

        // validator jailed
        await assertRevert(instance.unjail({from: accounts[7]}));

        // self delegation too low to unjail
        await instance.undelegate(accounts[7], web3.utils.toWei("0.5", "ether"), {from: accounts[7]});
        await assertRevert(instance.unjail({from: accounts[7]}));
    });


    it ("should mint", async () => {
        const instance = await Staking.deployed();
        await instance.setMintParams(0,0,5,0,0);
        const totalSupply = web3.utils.toWei("1000", "ether");
        const totalBonded = web3.utils.toWei("1", "ether");
        await instance.setTotalSupply(totalSupply);
        await instance.setTotalBonded(totalBonded);
        await instance.setInflation(0);
        await instance.setAnnualProvision(0);

        await instance.mint();

        // inflation min
        let inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.07", "ether")) // 7%

        const blockProvision = await instance.getBlockProvision.call();
        // 1000 * 7% / 5 = 14
        assert.equal(blockProvision.toString(),  web3.utils.toWei("14.000000000000000000", "ether"));

        await instance.mint();
        
        inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.095961729812476081", "ether"))

        await mint(5);

        // inflation max: 20%
        inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.2", "ether"));

        await instance.setTotalSupply(totalSupply);
        await instance.setTotalBonded(totalSupply);
        await instance.mint();

        inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.187194029850746269", "ether"));

        

        await mint(5); // 1 year
        let newTotalSupply = await instance.getTotalSupply.call();
        await instance.setTotalBonded(newTotalSupply.toString());

        await mint(5); // 1 year
        newTotalSupply = await instance.getTotalSupply.call();
        await instance.setTotalBonded(newTotalSupply.toString());

        await mint(5); // 1 year


        // inflation min : 7%
        inflation = await instance.getInflation.call();
        assert.equal(inflation.toString(), web3.utils.toWei("0.07", "ether")) // 7%


    })
})