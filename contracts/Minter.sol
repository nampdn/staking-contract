pragma solidity >=0.5.0;
import {Ownable} from "./Ownable.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {SafeMath} from "./Safemath.sol";

contract Minter is Ownable {
    using SafeMath for uint256;
    uint256 private _oneDec = 1 * 10**18;
    uint256 public inflationRateChange;
    uint256 public goalBonded;
    uint256 public blocksPerYear;
    uint256 public inflationMax;
    uint256 public inflationMin;

    uint256 public inflation;
    uint256 public annualProvision;
    uint256 public feesCollected;

    constructor() public {
        transferOwnership(msg.sender);
    }

    // @dev mints new tokens for the previous block. Returns fee collected
    function mint() public onlyOwner returns (uint256) {
        // recalculate inflation rate
        inflation = getNextInflationRate();
        // recalculate annual provisions
        annualProvision = getNextAnnualProvisions();
        // update fee collected
        feesCollected = getBlockProvision();
        return feesCollected;
    }

    function setInflation(uint256 _inflation) public onlyOwner {
        inflation = _inflation;
    }

    function getNextAnnualProvisions() public view returns (uint256) {
        uint256 totalSupply = IStaking(owner()).totalSupply();
        return inflation.mulTrun(totalSupply);
    }

    function getBlockProvision() public view returns (uint256) {
        return annualProvision.div(blocksPerYear);
    }

    function getNextInflationRate() public view returns (uint256) {
        uint256 totalBonded = IStaking(owner()).totalBonded();
        uint256 totalSupply = IStaking(owner()).totalSupply();
        uint256 bondedRatio = totalBonded.divTrun(totalSupply);
        uint256 inflationRateChangePerYear;
        uint256 infRateChange;
        uint256 inflationRate;
        if (bondedRatio < goalBonded) {
            inflationRateChangePerYear = _oneDec
                .sub(bondedRatio.divTrun(goalBonded))
                .mulTrun(inflationRateChange);
            infRateChange = inflationRateChangePerYear.div(
                blocksPerYear
            );
            inflationRate = inflation.add(inflationRateChange);
        } else {
            inflationRateChangePerYear = bondedRatio
                .divTrun(goalBonded)
                .sub(_oneDec)
                .mulTrun(inflationRateChange);
            infRateChange = inflationRateChangePerYear.div(
                blocksPerYear
            );
            if (inflation > inflationRateChange) {
                inflationRate = inflation.sub(inflationRateChange);
            } else {
                inflationRate = 0;
            }
        }
        if (inflationRate > inflationMax) {
            inflationRate = inflationMax;
        }
        if (inflationRate < inflationMin) {
            inflationRate = inflationMin;
        }
        return inflationRate;
    }
}