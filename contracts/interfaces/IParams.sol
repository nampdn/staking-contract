// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;


interface IParams {
    enum ParamKey {
        VotingPeriod,
        MaxValidator,
        Deposit,
        // add staking param key here
        // add validator params key here
    }

    function params(ParamKey key) external view returns (uint256)
}