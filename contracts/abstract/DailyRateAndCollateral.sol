// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "../vendor0.8/uniswap/FullMath.sol";
import "../libraries/Keys.sol";
import { Constants } from "../libraries/Constants.sol";

abstract contract DailyRateAndCollateral {
    /**
     * @dev Struct representing information about a token.
     * @param latestUpTimestamp The timestamp of the latest update for the token information.
     * @param accLoanRatePerSeconds The accumulated loan rate per second for the token.
     * @param currentDailyRate The current daily loan rate for the token.
     * @param totalBorrowed The total amount borrowed for the token.
     */
    struct TokenInfo {
        uint32 latestUpTimestamp;
        uint256 accLoanRatePerSeconds;
        uint256 currentDailyRate;
        uint256 totalBorrowed;
    }

    /// pairKey => TokenInfo
    mapping(bytes32 => TokenInfo) public holdTokenInfo;

    /**
     * @notice This internal view function retrieves the current daily rate for the hold token specified by `holdToken`
     * in relation to the sale token specified by `saleToken`. It also returns detailed information about the hold token rate stored
     * in the `holdTokenInfo` mapping. If the rate is not set, it defaults to `Constants.DEFAULT_DAILY_RATE`. If there are any existing
     * borrowings for the hold token, the accumulated loan rate per second is updated based on the time difference since the last update and the
     * current daily rate. The latest update timestamp is also recorded for future calculations.
     * @param saleToken The address of the sale token in the pair.
     * @param holdToken The address of the hold token in the pair.
     * @return currentDailyRate The current daily rate for the hold token.
     * @return holdTokenRateInfo The struct containing information about the hold token rate.
     */
    function _getHoldTokenRateInfo(
        address saleToken,
        address holdToken
    ) internal view returns (uint256 currentDailyRate, TokenInfo memory holdTokenRateInfo) {

        //@audit-info calc pair key
        bytes32 key = Keys.computePairKey(saleToken, holdToken);

        //@audit-info grab token info
        holdTokenRateInfo = holdTokenInfo[key];
        currentDailyRate = holdTokenRateInfo.currentDailyRate;
        if (currentDailyRate == 0) {
            currentDailyRate = Constants.DEFAULT_DAILY_RATE;
        }

        //@audit-info identical to _updateTokenRateInfo
        //@audit-info typical issue with rate difference
        //base on frequency of update but not valid med
        if (holdTokenRateInfo.totalBorrowed > 0) {
            uint256 timeWeightedRate = (uint32(block.timestamp) -
                holdTokenRateInfo.latestUpTimestamp) * currentDailyRate;
            holdTokenRateInfo.accLoanRatePerSeconds +=
                (timeWeightedRate * Constants.COLLATERAL_BALANCE_PRECISION) /
                1 days;
        }

        holdTokenRateInfo.latestUpTimestamp = uint32(block.timestamp);
    }

    /**
     * @notice This internal function updates the hold token rate information for the pair of sale token specified by `saleToken`
     * and hold token specified by `holdToken`. It retrieves the existing hold token rate information from the `holdTokenInfo` mapping,
     * including the current daily rate. If the current daily rate is not set, it defaults to `Constants.DEFAULT_DAILY_RATE`.
     * If there are any existing borrowings for the hold token, the accumulated loan rate per second is updated based on the time
     * difference since the last update and the current daily rate. Finally, the latest update timestamp is recorded for future calculations.
     * @param saleToken The address of the sale token in the pair.
     * @param holdToken The address of the hold token in the pair.
     * @return currentDailyRate The updated current daily rate for the hold token.
     * @return holdTokenRateInfo The struct containing the updated hold token rate information.
     */

    //@audit-info updates latestTimeStamp each time it's called
    function _updateTokenRateInfo(
        address saleToken,
        address holdToken
    ) internal returns (uint256 currentDailyRate, TokenInfo storage holdTokenRateInfo) {
        bytes32 key = Keys.computePairKey(saleToken, holdToken);
        holdTokenRateInfo = holdTokenInfo[key];
        currentDailyRate = holdTokenRateInfo.currentDailyRate;
        if (currentDailyRate == 0) {
            currentDailyRate = Constants.DEFAULT_DAILY_RATE;
        }
        if (holdTokenRateInfo.totalBorrowed > 0) {

            //@audit-info 0 dp + 4dp (10000)

            uint256 timeWeightedRate = (uint32(block.timestamp) -
                holdTokenRateInfo.latestUpTimestamp) * currentDailyRate;

            //@audit-info 4 dp + 18 dp = 22 dp
            holdTokenRateInfo.accLoanRatePerSeconds +=
                (timeWeightedRate * Constants.COLLATERAL_BALANCE_PRECISION) /
                1 days;
        }

        holdTokenRateInfo.latestUpTimestamp = uint32(block.timestamp);
    }

    /**
     * @notice This internal function calculates the collateral balance and current fees.
     * If the `borrowedAmount` is greater than 0, it calculates the fees based on the difference between the current accumulated
     * loan rate per second (`accLoanRatePerSeconds`) and the accumulated loan rate per share at the time of borrowing (`borrowingAccLoanRatePerShare`).
     * The fees are calculated using the FullMath library's `mulDivRoundingUp()` function, rounding up the result to the nearest integer.
     * The collateral balance is then calculated by subtracting the fees from the daily rate collateral at the time of borrowing (`borrowingDailyRateCollateral`).
     * Both the collateral balance and fees are returned as the function's output.
     * @param borrowedAmount The amount borrowed.
     * @param borrowingAccLoanRatePerShare The accumulated loan rate per share at the time of borrowing.
     * @param borrowingDailyRateCollateral The daily rate collateral at the time of borrowing.
     * @param accLoanRatePerSeconds The current accumulated loan rate per second.
     * @return collateralBalance The calculated collateral balance after deducting fees.
     * @return currentFees The calculated fees for the borrowing operation.
     */
    function _calculateCollateralBalance(
        uint256 borrowedAmount,
        uint256 borrowingAccLoanRatePerShare,
        uint256 borrowingDailyRateCollateral,
        uint256 accLoanRatePerSeconds
    ) internal pure returns (int256 collateralBalance, uint256 currentFees) {

        //@audit-info borrowedAmount = token dp for sure
        // accLoanRatePerSeconds = 22 dp
        // bp = 4 dp
        //@audit-info currentFees dp = token dp + 18 (22 - 4)
        //@audit-ok math checks out
        if (borrowedAmount > 0) {
            currentFees = FullMath.mulDivRoundingUp(
                borrowedAmount,
                accLoanRatePerSeconds - borrowingAccLoanRatePerShare,
                Constants.BP
            );

            //@audit-info both are actual token balance scaled by 1e18
            collateralBalance = int256(borrowingDailyRateCollateral) - int256(currentFees);
        }
    }
}
