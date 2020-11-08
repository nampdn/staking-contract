pragma solidity >=0.5.0;

interface IValidator {
    function initialize(uint64 commissionRate, uint64 commissionMaxRate, 
        uint64 commissionMaxChangeRate, uint64 minSelfDelegation) external payable;
    function update(uint64 commissionRate) external;
    function unjail() external;
    function allocateToken(uint64 amount) external;
    function slash() external;
    function jail() external;
    function delegate() external payable;
    function withdrawRewards() external;
    function withdrawCommission()external;
    function withdraw() external;
    function undelegate(uint64 amount) external;
    function getCommissionRewards() external view returns (uint64);
    function getDelegationRewards(address delAddr) external view returns (uint64);

}