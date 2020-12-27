const Params = artifacts.require("Params");
const Staking = artifacts.require("StakingTest");
const Validator = artifacts.require("Validator");
const utils = require("./utils");

function toWei(num) {
    return web3.utils.toWei(num, "ether")
}

contract("Staking", async (accounts) => {
    async function createValidator(account) {
        const instance = await Staking.deployed();
        const rate = web3.utils.toWei("0.4", "ether");
        const maxRate = web3.utils.toWei("0.5", "ether");
        const maxChangeRate = web3.utils.toWei("0.1", "ether");
        const name = web3.utils.fromAscii("val1");
        var selfDelegate =  web3.utils.toWei("0.1", "ether");
        await instance.createValidator(name, rate, maxRate, maxChangeRate, {from: account, value: selfDelegate});
        const valAddr = await instance.allVals.call(await instance.allValsLength() - 1);
        const val = await  Validator.at(valAddr);
        await val.delegate({from: account, value: web3.utils.toWei("1", "ether")});
        await val.start({from: account});
    }

    async function setup() {
        await createValidator(accounts[0]);
        await createValidator(accounts[1]);
        await createValidator(accounts[2]);
    }

    it("proposal", async () => {
        const staking = await Staking.deployed();
        await setup();
        const params = await Params.at(await staking.params()) 
        await utils.assertRevert(params.addProposal([0,1], [1,2]), "min deposit");

        // create proposal
        await params.addProposal([0,1], [1,2], {value: toWei("1")})

        // vote proposal
        await utils.assertRevert(params.addVote(1, 0), "proposal not found");
        await params.addVote(0, 1);
        await params.addVote(0, 2, {from: accounts[1]});

        // confirm proposal
        await utils.assertRevert(params.confirmProposal(1), "proposal not found");
        await utils.assertRevert(params.confirmProposal(0), "Inactive proposal");

        // rejected
        await utils.advanceTime(604801)
        await params.confirmProposal(0);
        let proposal = await params.proposals(0);
        assert.equal(proposal.status, 2);

        let results = await params.getProposalResults(0);
        assert.equal(await results[0].toString(), "110000000");
        assert.equal(await results[1].toString(), "110000000");
        assert.equal(await results[2].toString(), "110000000");

        await utils.assertRevert(params.confirmProposal(0), "proposal status pending");

        // passed
        await params.addProposal([0,1], [1,2], {value: toWei("1")});
        await params.addVote(1, 1);
        await params.addVote(1, 1, {from: accounts[1]});
        await params.addVote(1, 1, {from: accounts[2]});

        await utils.advanceTime(604801)
        await params.confirmProposal(1);
        proposal = await params.proposals(1);
        assert.equal(proposal.status, 1);
        assert.equal(await params.getParam(0), 1);
        assert.equal(await params.getParam(1), 2)

        results = await params.getProposalResults(1);
        assert.equal(await results[0].toString(), "330000000");
        assert.equal(await results[1].toString(), 0);
        assert.equal(await results[2].toString(), 0);
    })
})