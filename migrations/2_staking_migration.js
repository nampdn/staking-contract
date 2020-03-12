const Staking = artifacts.require("Staking");

module.exports = function(deployer) {
  deployer.deploy(Staking, 1, 1, 1, String(0.1 * Math.pow(10, 18)), String(0.01 * Math.pow(10, 18)), 100);
};



