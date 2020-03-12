const Staking = artifacts.require("Staking");

module.exports = function(deployer) {
  deployer.deploy(Staking, 1, 1, 1,  web3.utils.toWei("0.1", "ether"), web3.utils.toWei("0.01", "ether"), 100);
};



