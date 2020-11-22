// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IValidator {
    function initialize (
        bytes32 _name, 
        address _owner,
        uint256 _rate, 
        uint256 _maxRate, 
        uint256 _maxChangeRate, 
        uint256 _minSelfDelegation
    ) external;
    function update(bytes32 _name, uint256 _commissionRate, uint256 _minSelfDelegation) external;
    function unjail() external;
    function allocateToken(uint256 _rewards) external;
    function slash(uint256 _infrationHeight, uint256 _power, uint256 _slashFactor) external;
    function jail(uint256 _jailedUntil, bool _tombstoned) external;
    function delegate() external payable;
    function withdrawRewards() external;
    function withdrawCommission()external;
    function withdraw() external;
    function undelegate(uint256 _amount) external;
    function getCommissionRewards() external view returns (uint256);
    function getDelegationRewards(address _delAddr) external view returns (uint256);
    function validateSignature(uint256 _votingPower, bool _signed) external returns (bool);
    function doubleSign(
        uint256 votingPower,
        uint256 distributionHeight
    ) external;
}