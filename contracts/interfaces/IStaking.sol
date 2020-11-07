pragma solidity >=0.5.0;



interface IStaking {
    function create() external;
    function delegate() external;
    function undelegate() external;
    function finalize() external;
    function doubleSign() external;
    function mint() external;
}