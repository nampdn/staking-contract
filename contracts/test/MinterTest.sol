pragma solidity ^0.5.0;

import "../Minter.sol";


contract MinterTest is Minter {

    constructor() public {
        blocksPerYear = 5;
    }

    function setInflation(uint256 _inflation) public{
        inflation = _inflation;
    }

    function setAnnualProvision(uint256 _annualProvision) public{
        annualProvision = _annualProvision;
    }
}