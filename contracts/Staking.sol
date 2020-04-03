pragma solidity >=0.4.21 <0.7.0;
import {SafeMath} from "./Safemath.sol";



contract StakingNew {
    using SafeMath for uint256;

    struct Delegation {
        uint256 shares;
        address owner;
    }
    
    struct UBDEntry {
        uint256 amount;
        uint256 blockHeight;
        uint256 completionTime;
    }
    
    struct Validator {
        address owner;
        uint256 tokens;
        uint256 delegationShares;
        Delegation[] delegations;
    }
    
    struct DelegatorStartingInfo {
        uint256 stake;
        
    }
    
    mapping(address => Validator) validators;
    mapping(address => mapping(address => uint)) delegationsIndex;
    mapping(address => mapping(address => UBDEntry[])) unbondingEntries;
    mapping(address => mapping(address => DelegatorStartingInfo)) delegationStartingInfo;
    
    
    function _delegate(address delAddr, address valAddr, uint256 amount) private {
        Validator storage val = validators[valAddr];
        uint delIndex = delegationsIndex[valAddr][delAddr];
        
        // add delegation if not exists;
        if (delIndex == 0) {
            val.delegations.push(Delegation({
                owner: delAddr,
                shares: 0
            }));
            
            delegationsIndex[valAddr][delAddr] = val.delegations.length;
        }
        
        uint256 shared = val.delegationShares.mul(amount).div(val.tokens);
        
        // increment stake amount
        Delegation storage del = val.delegations[delIndex -1];
        del.shares = shared;
        val.tokens += amount;
        val.delegationShares += shared;
        
    }
    
    
    function delegate(address valAddr) public payable {
        require(validators[valAddr].owner != address(0x0), "validator does not exists");
        require(msg.value > 0, "invalid delegation amount");
        _delegate(msg.sender, valAddr, msg.value);
    }
    
    function _undelegate(address valAddr, address delAddr, uint256 amount) private {
        uint256 delegationIndex = delegationsIndex[valAddr][delAddr];
        Validator storage val = validators[valAddr];
        Delegation storage del = val.delegations[delegationIndex -1];
        uint256 shares = val.delegationShares.mul(amount).div(val.tokens);
        uint256 token = shares.mul(val.tokens).div(val.delegationShares);
        val.delegationShares -= shares;
        val.tokens -=token;
        del.shares -=shares;
        
        unbondingEntries[valAddr][delAddr].push(UBDEntry({
            completionTime: 1,
            blockHeight: block.number,
            amount: token
        }));
        
    }
    
    
    function _slash(address valAddr, uint256 infrationHeight, uint256 power, uint256 slashFactor) private {
        require(infrationHeight <= block.number, "");
        Validator storage val = validators[valAddr];
        uint256 slashAmount = power.mul(slashFactor);
        if (infrationHeight < block.number) {
            for (uint i = 0; i < val.delegations.length; i ++) {
                UBDEntry[] storage entries = unbondingEntries[valAddr][val.delegations[i].owner];
                for (uint j = 0; j < entries.length; j ++) {
                    UBDEntry storage entry = entries[j];
                    if (entry.blockHeight > infrationHeight) {
                        uint256 amountSlashed = entry.amount.mul(slashFactor);
                        entry.amount -= amountSlashed;
                        slashAmount -= amountSlashed;
                    }
                }
            }
        }
        val.tokens -= slashAmount;
    }
    
    
    function _withdrawl(address valAddr, address delAddr, uint256) private returns (uint256){
        UBDEntry[] storage entries= unbondingEntries[valAddr][delAddr];
        uint256 amount = 0;
        for (uint i = 0; i < entries.length; i ++) {
            if (entries[i].completionTime < block.timestamp) {
                amount += entries[i].amount;
                entries[i] = entries[entries.length - 1];
                entries.pop();
            }
        }
        return amount;
    }
    
    
    function _withdrawlReward(address valAddr, address delAddr) private returns(uint256) {
        
    }
    
}