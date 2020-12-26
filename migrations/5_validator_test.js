const ValidatorTest = artifacts.require("Validator");

module.exports = function(deployer) {
  deployer.deploy(ValidatorTest);
};

