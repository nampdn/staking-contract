pragma solidity ^0.5.0;
import {Ownable} from "./Ownable.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {SafeMath} from "./Safemath.sol";
import {IParams} from "./interfaces/IParams.sol";


contract Params is Ownable {
    using SafeMath for uint256;
    uint256 private _oneDec = 1 * 10**18;

    struct StakingParams {
        uint256 baseProposerReward;
        uint256 bonusProposerReward;
        uint256 maxValidators;
    }

    struct ValidatorParams {
        uint256 downtimeJailDuration;
        uint256 slashFractionDowntime;
        uint256 unbondingTime;
        uint256 slashFractionDoubleSign;
        uint256 signedBlockWindow;
        uint256 minSignedPerWindow;
        uint256 minStake;
        uint256 minValidatorBalance;
    }

    struct MintParams {
        uint256 inflationRateChange;
        uint256 goalBonded;
        uint256 blocksPerYear;
        uint256 inflationMax;
        uint256 inflationMin;
    }

    IStaking private _staking;
    StakingParams public stakingParams;
    ValidatorParams public validatorParams;
    MintParams public mintParams;

    constructor() public {
        transferOwnership(msg.sender);
        _staking = IStaking(msg.sender);

        stakingParams = StakingParams({
            baseProposerReward: 1 * 10**16,
            bonusProposerReward: 4 * 10**16,
            maxValidators: 21
        });

        validatorParams = ValidatorParams({
            downtimeJailDuration: 600,
            slashFractionDowntime: 1 * 10**14,
            unbondingTime: 1814400, 
            slashFractionDoubleSign: 5 * 10**16,
            signedBlockWindow: 10000,
            minSignedPerWindow: 5 * 10**16,
            minStake: 1 * 10**16, // 10 000 kai
            minValidatorBalance: 1 * 10**17
        });

        mintParams = MintParams({
            inflationRateChange: 5 * 10**16, // 5%
            goalBonded: 35 * 10**16,
            blocksPerYear: 6307200,
            inflationMax: 7 * 10**16,
            inflationMin: 2 * 10**16
        });

    }

    function updateBaseReward(uint256 _baseProposerReward, uint256 _bonusProposerReward) external onlyOwner {
        stakingParams.baseProposerReward = _baseProposerReward;
        stakingParams.bonusProposerReward = _bonusProposerReward;
    }

    function updateMaxValidator(uint256 _maxValidators) external onlyOwner {
        stakingParams.maxValidators = _maxValidators;
    }

    function updateValidatorParams(
        uint256 _downtimeJailDuration,
        uint256 _slashFractionDowntime,
        uint256 _unbondingTime,
        uint256 _slashFractionDoubleSign,
        uint256 _signedBlockWindow,
        uint256 _minSignedPerWindow,
        uint256 _minStake,
        uint256 _minValidatorBalance) 
        external onlyOwner {
        
        validatorParams = ValidatorParams({
            downtimeJailDuration: _downtimeJailDuration,
            slashFractionDowntime: _slashFractionDowntime,
            unbondingTime: _unbondingTime, 
            slashFractionDoubleSign: _slashFractionDoubleSign,
            signedBlockWindow: _signedBlockWindow,
            minSignedPerWindow: _minSignedPerWindow,
            minStake: _minStake, // 10 000 kai
            minValidatorBalance: _minValidatorBalance
        });
    }

    function updateMintParams(
        uint256 _inflationRateChange,
        uint256 _goalBonded,
        uint256 _blocksPerYear,
        uint256 _inflationMax,
        uint256 _inflationMin
    ) external onlyOwner {

        mintParams = MintParams({
            inflationRateChange: _inflationRateChange, // 5%
            goalBonded: _goalBonded,
            blocksPerYear: _blocksPerYear,
            inflationMax: _inflationMax,
            inflationMin: _inflationMin
        });
    }

    function getBaseProposerReward() external view returns (uint256) {
        return stakingParams.baseProposerReward;
    }

    function getBonusProposerReward() external view returns (uint256) {
        return stakingParams.bonusProposerReward;
    }

    function getMaxValidators() external view returns (uint256) {
        return stakingParams.maxValidators;
    }

    function getInflationRateChange() external view returns (uint256) {
        return mintParams.inflationRateChange;
    }

    function getGoalBonded() external view returns (uint256) {
        return mintParams.goalBonded;
    }

    function getBlocksPerYear() external view returns (uint256) {
        return mintParams.blocksPerYear;
    }

    function getInflationMax() external view returns (uint256) {
        return mintParams.inflationMax;
    }

    function getInflationMin() external view returns (uint256) {
        return mintParams.inflationMin;
    }

    function getDowntimeJailDuration() external view returns (uint256) {
        return validatorParams.downtimeJailDuration;
    }

    function getSlashFractionDowntime() external view returns (uint256) {
        return validatorParams.slashFractionDowntime;
    }

    function getUnbondingTime() external view returns (uint256) {
        return validatorParams.unbondingTime;
    }

    function getSlashFractionDoubleSign() external view returns (uint256) {
        return validatorParams.slashFractionDoubleSign;
    }

    function getSignedBlockWindow() external view returns (uint256) {
        return validatorParams.signedBlockWindow;
    }

    function getMinSignedPerWindow() external view returns (uint256) {
        return validatorParams.minSignedPerWindow;
    }

    function getMinStake() external view returns (uint256) {
        return validatorParams.minStake;
    }

    function getMinValidatorBalance() external view returns (uint256) {
        return validatorParams.minValidatorBalance;
    }
}