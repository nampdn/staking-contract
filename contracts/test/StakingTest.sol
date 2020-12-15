pragma solidity ^0.5.0;

import "../Staking.sol";
import "./MinterTest.sol";
import {Params} from "../Params.sol";


contract StakingTest is Staking {

    function createMinterTest() public{
       minter =  new MinterTest();
    }

    function setPreviousProposer(address previousProposer) public {
        _previousProposer = previousProposer;
    }

    function setTotalBonded(uint256 amount) public {
        totalBonded = amount;
    }

    function setTotalSupply(uint256 amount) public {
        totalSupply = amount;
    }
}