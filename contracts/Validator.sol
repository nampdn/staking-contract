pragma solidity >=0.5.0;
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./interfaces/IValidator.sol";


contract Validator is IValidator {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Delegation
    struct Delegation {
        uint256 stake;
        uint256 previousPeriod;
        uint256 height;
    }

    // Validator Commission
    struct Commission {
        uint64 rate;
        uint64 maxRate;
        uint64 maxChangeRate;
    }

    // Unbounding Entry
    struct UBDEntry {
        uint256 amount;
        uint256 blockHeight;
        uint256 completionTime;
    }

    // validator slash event
    struct SlashEvent {
        uint256 period;
        uint256 fraction;
        uint256 height;
    }

    // Validator current rewards
    struct CurrentReward {
        uint256 period;
        uint256 reward;
    }

    // Validator Historical Reward
    struct HistoricalReward {
        uint256 cumulativeRewardRatio;
        uint256 referenceCount;
    }

    struct SigningInfo {
        uint256 startHeight;
        uint256 indexOffset;
        bool tombstoned;
        uint256 missedBlockCounter;
        uint256 jailedUntil;
    }

     struct MissedBlock {
        mapping(uint256 => bool) items;
    }


    string name; // validator name
    EnumerableSet.AddressSet private delegations; // all delegations
    mapping(address => Delegation) public delegationByAddr; // delegation by address
    Commission public commission; // validator commission
    CurrentReward private currentRewwards // current validator rewards
    HistoricalReward private historicalRewards // historical rewards
    SlashEvent[] private slashEvents // slash events
    SigningInfo private signingInfo // signing info
    MissedBlock public missedBlock // missed block


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


    // undelegate
    function undelegate(uint64 amount) external {
        
    }
}