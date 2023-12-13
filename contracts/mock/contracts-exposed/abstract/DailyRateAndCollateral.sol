// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "../../../../contracts/abstract/DailyRateAndCollateral.sol";

contract $DailyRateAndCollateral is DailyRateAndCollateral {
    bytes32 public constant __hh_exposed_bytecode_marker = "hardhat-exposed";

    event return$_updateTokenRateInfo(uint256 currentDailyRate, TokenInfo holdTokenRateInfo);

    constructor() payable {}

    function $_getHoldTokenRateInfo(
        address saleToken,
        address holdToken
    ) external view returns (uint256 currentDailyRate, TokenInfo memory holdTokenRateInfo) {
        (currentDailyRate, holdTokenRateInfo) = super._getHoldTokenRateInfo(saleToken, holdToken);
    }

    function $_updateTokenRateInfo(
        address saleToken,
        address holdToken
    ) external returns (uint256 currentDailyRate, TokenInfo memory holdTokenRateInfo) {
        (currentDailyRate, holdTokenRateInfo) = super._updateTokenRateInfo(saleToken, holdToken);
        emit return$_updateTokenRateInfo(currentDailyRate, holdTokenRateInfo);
    }

    function $_calculateCollateralBalance(
        uint256 borrowedAmount,
        uint256 borrowingAccLoanRatePerShare,
        uint256 borrowingDailyRateCollateral,
        uint256 accLoanRatePerSeconds
    ) external pure returns (int256 collateralBalance, uint256 currentFees) {
        (collateralBalance, currentFees) = super._calculateCollateralBalance(
            borrowedAmount,
            borrowingAccLoanRatePerShare,
            borrowingDailyRateCollateral,
            accLoanRatePerSeconds
        );
    }

    receive() external payable {}
}
