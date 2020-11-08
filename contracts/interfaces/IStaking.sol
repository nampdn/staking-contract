pragma solidity >=0.5.0;

interface IStaking {
    function createValidator(uint64 commissionRate, uint64 commissionMaxRate, 
        uint64 commissionMaxChangeRate, uint64 minSelfDelegation) external returns (address);
    function finalize(address[] memory vals, uint64[] memory votingPower, bool[] memory signed) external;
    function doubleSign(address valAddr, uint64 votingPower, uint64 height) external;
    function mint() external returns (uint64);
    function getTotalSupply() external returns (uint64);
    function getTotalBonded() external returns (uint64);
}