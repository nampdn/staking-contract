const Staking = artifacts.require("Staking");

module.exports = function(deployer) {
  const maxValidators= 4;
  const maxMissed = 500; // 500 block
  const downtimeJailDuration = 60*60*24*30; // 30 days
  const baseProposerReward = web3.utils.toWei("0.1", "ether"); // 10%
  const bonusProposerReward = web3.utils.toWei("0.01", "ether"); // 1%
  const slashFractionDowntime = web3.utils.toWei("0.1", "ether"); // 10%
  const unboudingTime = 1 // 1s for testing
  const slashFractionDoubleSign = web3.utils.toWei("0.5", "ether"); // 50%

  deployer.deploy(Staking, maxValidators, maxMissed, downtimeJailDuration, baseProposerReward, 
    bonusProposerReward, slashFractionDowntime, unboudingTime, slashFractionDoubleSign);
};



