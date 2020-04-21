const Staking = artifacts.require("Staking");

contract("Mint", async (accounts) => {

    before(async () => {
        let instance = await Staking.deployed();
        await instance.setRoot(accounts[0], {from: accounts[0]});
    });

    async function mint(num) {
        const instance = await Staking.deployed();
        for (var i =0; i < num; i ++) {
            await instance.mint();
        }
    }

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
});