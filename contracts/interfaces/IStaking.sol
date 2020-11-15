// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IStaking {
    function createValidator(
        bytes32 name,
        uint256 commissionRate, 
        uint256 commissionMaxRate, 
        uint256 commissionMaxChangeRate, 
        uint256 minSelfDelegation
    ) external returns (address val);
    function finalize(
        address[] calldata _vals, 
        uint256[] calldata _votingPower, 
        bool[] calldata _signed
    ) external;
    // function doubleSign(address valAddr, uint64 votingPower, uint64 height) external;
    function mint() external returns (uint256 fees);
    function totalSupply() external view returns (uint64);
    function totalBonded() external view returns (uint64);
    function allValsLength() external view returns (uint);
    function delegate(address delAddr, uint256 amount) external;
    // function undelegate(uint64 amount) external;
    // function burn(uint64 amount) external;
    // function removeDelegation(address delAddr) external;
    // function getValidatorsByDelegator(address delAddr)  external view returns (address[] memory);
    // function applyAndReturnValidatorSets() external returns (address[] memory, uint256[] memory);
    // function getValidatorsByDelegator() external view returns (address[] memory);
}