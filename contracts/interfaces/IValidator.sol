pragma solidity >=0.5.0;

interface IValidator {
    function initialize (string calldata _name, address _valAddr, uint256 _rate, uint256 _maxRate, 
        uint256 _maxChangeRate, uint256 _minSelfDelegation, uint256 _amount) external;
    function update(uint256 _commissionRate) external;
    function unjail() external;
    function allocateToken(uint256 _rewards) external;
    function slash(uint256 _infrationHeight, uint256 _power, uint256 _slashFactor) external;
    function jail(uint64 jailedUntil, bool tombstoned) external;
    function delegate() external payable;
    function withdrawRewards() external;
    function withdrawCommission()external;
    function withdraw() external;
    function undelegate(uint256 _amount) external;
    function getCommissionRewards() external view returns (uint256);
    function getDelegationRewards(address _delAddr) external view returns (uint256);
    function validateSignature(uint64 votingPower, bool signed) external;

}