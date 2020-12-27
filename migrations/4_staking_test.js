const StakingTest = artifacts.require("StakingTest");

module.exports = function(deployer) {
  deployer.deploy(StakingTest);
};

