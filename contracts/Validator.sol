pragma solidity >=0.5.0;
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./interfaces/IValidator.sol";


contract Validator is IValidator {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Delegation {
        uint256 stake;
        uint256 previousPeriod;
        uint256 height;
    }

    struct Commission {
        uint64 rate;
        uint64 maxRate;
        uint64 maxChangeRate;
    }

    struct UBDEntry {
        uint256 amount;
        uint256 blockHeight;
        uint256 completionTime;
    }

     struct DelStartingInfo {
        uint256 stake;
        uint256 previousPeriod;
        uint256 height;
    }

    struct ValSlashEvent {
        uint256 validatorPeriod;
        uint256 fraction;
        uint256 height;
    }

    struct ValCurrentReward {
        uint256 period;
        uint256 reward;
    }

    string name; // validator name
    EnumerableSet.AddressSet private delegations; // all delegations
    mapping(address => Delegation) public delegationByAddr; // delegation by address
    Commission public commission; // validator commission


    // called one by the staking at time of deployment  
    function initialize(_name string, uint64 rate, uint64 maxRate, uint64 maxChangeRate) external {
        name = name;
        commission = Commission{
            maxRate: maxRate,
            maxChangeRate: maxChangeRate,
            rate: rate,
        }
    }
    
    // delegate for this validator
    function delegate() external payable {
        Delegation storage del = delegationByAddr[msg.sender]
        del.share = 1;
    }
}