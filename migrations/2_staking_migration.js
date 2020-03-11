const Staking = artifacts.require("Staking");

module.exports = function(deployer) {
  deployer.deploy(Staking, 1, 1, 1);
};
