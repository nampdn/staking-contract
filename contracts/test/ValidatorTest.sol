pragma solidity >=0.5.0;

import "../Validator.sol";


contract ValidatorTest is Validator {
    function setParamsTest() public {
        params.signedBlockWindow = 2;
        params.minSignedPerWindow = 50 * 10**16;
    }
}