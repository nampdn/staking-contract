const ValidatorTest = artifacts.require("ValidatorTest");

module.exports = function(deployer) {
  deployer.deploy(ValidatorTest);
};

