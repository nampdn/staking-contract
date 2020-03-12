const Staking = artifacts.require("Staking");

module.exports = function(deployer) {
  deployer.deploy(Staking, 1, 1, 1, String(1 * Math.pow(10, 18)), 100, 100);
};



