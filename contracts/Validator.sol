pragma solidity >=0.5.0;
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./interfaces/IValidator.sol";


contract Validator is IValidator {
    using EnumerableSet for EnumerableSet.AddressSet;
    uint256 oneDec = 1 * 10**18;

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
    address public stakingAddr; // staking address
    uint256 minSelfDelegation; 
    uint64 tokens; // all token stake
    uint256 delegationShares; // delegation shares


    // called one by the staking at time of deployment  
    function initialize(_name string, address _stakingAddr, uint64 rate, uint64 maxRate, 
        uint64 maxChangeRate, uint64 _minSelfDelegation) external {
        name = name;
        minSelfDelegation = _minSelfDelegation
        stakingAddr = _stakingAddr
        commission = Commission{
            maxRate: maxRate,
            maxChangeRate: maxChangeRate,
            rate: rate,
        }
    }

    
    // delegate for this validator
    function delegate() external payable {
        _delegate(msg.sender, msg.value)
    }

    function _delegate(address delAddr, uint256 amount) private{
        uint256 shared = _addTokenFromDel(valAddr, amount);
        // increment stake amount
        Delegation storage del = delegationByAddr[delAddr];
        del.shares = shared
    }

    function _addToken(uint64 amount) private returns(uint256) {
        uint256 issuedShares = 0;
        if (val.tokens == 0) {
            issuedShares = oneDec;
        } else {
            issuedShares = _shareFromToken(valAddr, amount);
        }
        tokens = tokens.add(amount)
        delegationShares = delegationShares.add(issuedShares)
        return delegationShares;
    }


    function _shareFromToken(uint64 amount) private view returns(uint256){
        return delegationShares.mul(amount).div(tokens)
    }


    // undelegate
    function undelegate(uint64 amount) external {
        
    }
}