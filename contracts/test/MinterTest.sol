pragma solidity ^0.5.0;

import "../Minter.sol";
import {Params} from "../Params.sol";


contract MinterTest is Minter {
    address paramsInit =0x4C4662D27def3AC032aB93dd497ca15A9f6D14de;
    constructor() Minter(paramsInit)public {
    }

    function setInflation(uint256 _inflation) public{
        inflation = _inflation;
    }

    function setAnnualProvision(uint256 _annualProvision) public{
        annualProvision = _annualProvision;
    }

    function setParams(address _params) public {
        params = _params;
    }
}