pragma solidity ^0.5.0;

import "../Staking.sol";
import "./MinterTest.sol";
import "./ParamsTest.sol";


contract StakingTest is Staking {

    function createMinterTest() public{
       minter =  new MinterTest();
    }

    function createParamsTest() public {
        params = address(new ParamsTest());
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