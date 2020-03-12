const Staking = artifacts.require("Staking");

module.exports = function(deployer) {
  const maxValidators= 4;
  const maxMissed = 50; // max missed 50 block
  const downtimeJailDuration = 60*60*24*30; // 30 days
  const baseProposerReward = web3.utils.toWei("0.1", "ether"); // 10%
  const bonusProposerReward = web3.utils.toWei("0.01", "ether"); // 1%
  const slashFractionDowntime = web3.utils.toWei("0.1", "ether"); // 10%
  deployer.deploy(Staking, maxValidators, maxMissed, downtimeJailDuration, baseProposerReward, bonusProposerReward, slashFractionDowntime);
};



