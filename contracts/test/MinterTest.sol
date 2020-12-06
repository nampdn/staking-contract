pragma solidity >=0.5.0;

import "../Minter.sol";


contract MinterTest is Minter {

    constructor() public {
        blocksPerYear = 5;
    }
}