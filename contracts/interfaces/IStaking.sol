// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IStaking {
    function createValidator(uint64 commissionRate, uint64 commissionMaxRate, 
        uint64 commissionMaxChangeRate, uint64 minSelfDelegation) external;
    function finalize(address[] calldata vals, uint64[] calldata votingPower, bool[] calldata signed) external;
    function doubleSign(address valAddr, uint64 votingPower, uint64 height) external;
    function mint() external returns (uint64);
    function updateValidatorAmount(uint64 amount) external;
    function totalSupply() external view returns (uint64);
    function totalBonded() external view returns (uint64);
    function delegate(address delAddr, uint64 amount) external;
    function undelegate(uint64 amount) external;
    function burn(uint64 amount) external;
    function removeDelegation(address delAddr) external;
    function getValidatorsByDelegator(address delAddr)  external view returns (address[] memory);
    function applyAndReturnValidatorSets() external returns (address[] memory, uint256[] memory);
    function getValidatorsByDelegator() external view returns (address[] memory);
}