pragma solidity >=0.5.0;

import "../Staking.sol";
import "./ValidatorTest.sol";


contract StakingTest is Staking {
    function setPreviousProposer(address previousProposer) public {
        _previousProposer = previousProposer;
    }
    
    function setMaxValidator(uint256 _maxValidator) public {
        params.maxValidator = _maxValidator;
    }

    // create new validator
    function createValidatorTest(
        bytes32 name,
        uint256 rate, 
        uint256 maxRate, 
        uint256 maxChangeRate, 
        uint256 minSelfDelegation
    ) external returns (address val) {
        require(ownerOf[msg.sender] == address(0x0), "Valdiator owner exists");
        require(
            maxRate <= 1 * 10 ** 18,
            "commission max rate cannot be more than 100%"
        );
        require(
            maxChangeRate <= maxRate,
            "commission max change rate can not be more than the max rate"
        );
        require(
            rate <= maxRate,
            "commission rate cannot be more than the max rate"
        );


        bytes memory bytecode = type(ValidatorTest).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(name, rate, maxRate, 
            maxChangeRate, minSelfDelegation, msg.sender));
        assembly {
            val := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IValidator(val).initialize(name, msg.sender, rate, maxRate, 
            maxChangeRate, minSelfDelegation);
        
        emit CreatedValidator(
            name,msg.sender,rate,
            maxRate,maxChangeRate,minSelfDelegation
        );

        allVals.push(val);
        ownerOf[msg.sender] = val;
        valOf[val] = msg.sender;
    }
}