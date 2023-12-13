// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

/// @title Constant state
library Constants {
    uint256 public constant BP = 10000;
    uint256 public constant BPS = 1000;
    uint256 public constant DEFAULT_DAILY_RATE = 10; // 0.1%
    uint256 public constant MAX_PLATFORM_FEE = 2000; // 20%
    uint256 public constant MAX_LIQUIDATION_BONUS = 100; // 1%
    uint256 public constant MAX_DAILY_RATE = 100; // 1%
    uint256 public constant MIN_DAILY_RATE = 5; // 0.05 %
    uint256 public constant MAX_NUM_LOANS_PER_POSITION = 7;
    uint256 public constant MAX_NUM_USER_POSOTION = 10;
    uint256 public constant COLLATERAL_BALANCE_PRECISION = 1e18;
    uint256 public constant MINIMUM_AMOUNT = 1000;
    uint256 public constant MINIMUM_BORROWED_AMOUNT = 100000;
}
