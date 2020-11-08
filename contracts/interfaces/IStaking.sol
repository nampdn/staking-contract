pragma solidity >=0.5.0;



interface IStaking {
    function createValidator() external;
    function finalize() external;
    function doubleSign() external;
    function mint() external;
    function getTotalSupply() external;
    function getTotalBonded() external;
}