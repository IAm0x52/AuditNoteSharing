// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "../vendor0.8/uniswap/LiquidityAmounts.sol";
import "../vendor0.8/uniswap/TickMath.sol";
import "../interfaces/INonfungiblePositionManager.sol";
import "../interfaces/IQuoterV2.sol";
import "./ApproveSwapAndPay.sol";
import "../Vault.sol";
import { Constants } from "../libraries/Constants.sol";

abstract contract LiquidityManager is ApproveSwapAndPay {
    /**
     * @notice Represents information about a loan.
     * @dev This struct is used to store liquidity and tokenId for a loan.
     * @param liquidity The amount of liquidity for the loan represented by a uint128 value.
     * @param tokenId The token ID associated with the loan represented by a uint256 value.
     */
    struct LoanInfo {
        uint128 liquidity;
        uint256 tokenId;
    }
    /**
     * @notice Contains parameters for restoring liquidity.
     * @dev This struct is used to store various parameters required for restoring liquidity.
     * @param zeroForSaleToken A boolean value indicating whether the token for sale is the 0th token or not.
     * @param fee The fee associated with the internal swap pool is represented by a uint24 value.
     * @param slippageBP1000 The slippage in basis points (BP) represented by a uint256 value.
     * @param totalfeesOwed The total fees owed represented by a uint256 value.
     * @param totalBorrowedAmount The total borrowed amount represented by a uint256 value.
     */
    struct RestoreLiquidityParams {
        bool zeroForSaleToken;
        uint24 fee;
        uint256 slippageBP1000;
        uint256 totalfeesOwed;
        uint256 totalBorrowedAmount;
    }
    /**
     * @notice Contains cache data for restoring liquidity.
     * @dev This struct is used to store cached values required for restoring liquidity.
     * @param tickLower The lower tick boundary represented by an int24 value.
     * @param tickUpper The upper tick boundary represented by an int24 value.
     * @param fee The fee associated with the restoring liquidity pool.
     * @param saleToken The address of the token being sold.
     * @param holdToken The address of the token being held.
     * @param sqrtPriceX96 The square root of the price represented by a uint160 value.
     * @param holdTokenDebt The debt amount associated with the hold token represented by a uint256 value.
     */
    struct RestoreLiquidityCache {
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        address saleToken;
        address holdToken;
        uint160 sqrtPriceX96;
        uint256 holdTokenDebt;
    }
    /**
     * @notice The address of the vault contract.
     */
    address public immutable VAULT_ADDRESS;
    /**
     * @notice The Nonfungible Position Manager contract.
     */

    //@audit-info uniswap position manager
    //@audit-info check if this is possible to deploy on all these networks
    INonfungiblePositionManager public immutable underlyingPositionManager;
    /**
     * @notice The QuoterV2 contract.
     */
    IQuoterV2 public immutable underlyingQuoterV2;

    /**
     * @dev Contract constructor.
     * @param _underlyingPositionManagerAddress Address of the underlying position manager contract.
     * @param _underlyingQuoterV2 Address of the underlying quoterV2 contract.
     * @param _underlyingV3Factory Address of the underlying V3 factory contract.
     * @param _underlyingV3PoolInitCodeHash The init code hash of the underlying V3 pool.
     */
    constructor(
        address _underlyingPositionManagerAddress,
        address _underlyingQuoterV2,
        address _underlyingV3Factory,
        bytes32 _underlyingV3PoolInitCodeHash
    ) ApproveSwapAndPay(_underlyingV3Factory, _underlyingV3PoolInitCodeHash) {

        //@audit-info just a bunch of setters

        // Assign the underlying position manager contract address
        underlyingPositionManager = INonfungiblePositionManager(_underlyingPositionManagerAddress);
        // Assign the underlying quoterV2 contract address
        underlyingQuoterV2 = IQuoterV2(_underlyingQuoterV2);
        // Generate a unique salt for the new Vault contract
        bytes32 salt = keccak256(abi.encode(block.timestamp, address(this)));
        // Deploy a new Vault contract using the generated salt and assign its address to VAULT_ADDRESS
        VAULT_ADDRESS = address(new Vault{ salt: salt }());
    }

    error InvalidBorrowedLiquidity(uint256 tokenId);
    error TooLittleBorrowedLiquidity(uint128 liquidity);
    error InvalidTokens(uint256 tokenId);
    error NotApproved(uint256 tokenId);
    error InvalidRestoredLiquidity(
        uint256 tokenId,
        uint128 borrowedLiquidity,
        uint128 restoredLiquidity,
        uint256 amount0,
        uint256 amount1,
        uint256 holdTokentBalance,
        uint256 saleTokenBalance
    );

    /**
     * @dev Calculates the borrowed amount from a pool's single side position, rounding up if necessary.
     * @param zeroForSaleToken A boolean value indicating whether the token for sale is the 0th token or not.
     * @param tickLower The lower tick value of the position range.
     * @param tickUpper The upper tick value of the position range.
     * @param liquidity The liquidity of the position.
     * @return borrowedAmount The calculated borrowed amount.
     */
    function _getSingleSideRoundUpBorrowedAmount(
        bool zeroForSaleToken,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) private pure returns (uint256 borrowedAmount) {
        borrowedAmount = (
            zeroForSaleToken
                ? LiquidityAmounts.getAmount1ForLiquidity(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidity
                )
                : LiquidityAmounts.getAmount0ForLiquidity(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liquidity
                )
        );
        if (borrowedAmount > Constants.MINIMUM_BORROWED_AMOUNT) {
            ++borrowedAmount;
        } else {
            revert TooLittleBorrowedLiquidity(liquidity);
        }
    }

    /**
     * @dev Extracts liquidity from loans and returns the borrowed amount.
     * @param zeroForSaleToken A boolean value indicating whether the token for sale is the 0th token or not.
     * @param token0 The address of one of the tokens in the pair.
     * @param token1 The address of the other token in the pair.
     * @param loans An array of LoanInfo struct instances containing loan information.
     * @return borrowedAmount The total amount borrowed.
     */

    //@audit-issue this has a LOT of attack surface
    function _extractLiquidity(
        bool zeroForSaleToken,
        address token0,
        address token1,
        LoanInfo[] memory loans
    ) internal returns (uint256 borrowedAmount) {

        //@audit-info reverse ordering
        if (!zeroForSaleToken) {
            (token0, token1) = (token1, token0);
        }

        //
        for (uint256 i; i < loans.length; ) {
            uint256 tokenId = loans[i].tokenId;
            uint128 liquidity = loans[i].liquidity;
            // Extract position-related details
            {
                int24 tickLower;
                int24 tickUpper;
                uint128 posLiquidity;
                {
                    address operator;
                    address posToken0;
                    address posToken1;

                    (
                        ,
                        operator,
                        posToken0,
                        posToken1,
                        ,
                        tickLower,
                        tickUpper,
                        posLiquidity,
                        ,
                        ,
                        ,

                    ) = underlyingPositionManager.positions(tokenId);
                    // Check operator approval
                    if (operator != address(this)) {
                        revert NotApproved(tokenId);
                    }
                    // Check token validity
                    if (posToken0 != token0 || posToken1 != token1) {
                        revert InvalidTokens(tokenId);
                    }
                }
                // Check borrowed liquidity validity

                //@audit-info confirms that position liquidity is
                //higher than requested liquidity
                if (!(liquidity > 0 && liquidity <= posLiquidity)) {
                    revert InvalidBorrowedLiquidity(tokenId);
                }
                // Calculate borrowed amount
                borrowedAmount += _getSingleSideRoundUpBorrowedAmount(
                    zeroForSaleToken,
                    tickLower,
                    tickUpper,
                    liquidity
                );
            }
            // Decrease liquidity and move to the next loan
            _decreaseLiquidity(tokenId, liquidity);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Restores liquidity from loans.
     * @param params The RestoreLiquidityParams struct containing restoration parameters.
     * @param externalSwap The SwapParams struct containing external swap details.
     * @param loans An array of LoanInfo struct instances containing loan information.
     */
    function _restoreLiquidity(
        // Create a cache struct to store temporary data
        RestoreLiquidityParams memory params,
        SwapParams calldata externalSwap,
        LoanInfo[] memory loans
    ) internal {
        RestoreLiquidityCache memory cache;
        for (uint256 i; i < loans.length; ) {
            // Update the cache for the current loan
            LoanInfo memory loan = loans[i];
            _upRestoreLiquidityCache(params.zeroForSaleToken, loan, cache);
            // Calculate the hold token amount to be used for swapping
            (uint256 holdTokenAmountIn, uint256 amount0, uint256 amount1) = _getHoldTokenAmountIn(
                params.zeroForSaleToken,
                cache.tickLower,
                cache.tickUpper,
                cache.sqrtPriceX96,
                loan.liquidity,
                cache.holdTokenDebt
            );

            if (holdTokenAmountIn > 0) {
                // Quote exact input single for swap
                uint256 saleTokenAmountOut;
                (saleTokenAmountOut, cache.sqrtPriceX96, , ) = underlyingQuoterV2
                    .quoteExactInputSingle(
                        IQuoterV2.QuoteExactInputSingleParams({
                            tokenIn: cache.holdToken,
                            tokenOut: cache.saleToken,
                            amountIn: holdTokenAmountIn,
                            fee: params.fee,
                            sqrtPriceLimitX96: 0
                        })
                    );

                // Perform external swap if external swap target is provided

                //@audit-info attacker can break slippage controls
                //by sandwich attacking the underlying UniV3 pool
                //@audit report submitted
                if (externalSwap.swapTarget != address(0)) {
                    _patchAmountsAndCallSwap(
                        cache.holdToken,
                        cache.saleToken,
                        externalSwap,
                        holdTokenAmountIn,
                        (saleTokenAmountOut * params.slippageBP1000) / Constants.BPS
                    );
                } else {
                    // Calculate hold token amount in again for new sqrtPriceX96
                    (holdTokenAmountIn, , ) = _getHoldTokenAmountIn(
                        params.zeroForSaleToken,
                        cache.tickLower,
                        cache.tickUpper,
                        cache.sqrtPriceX96,
                        loan.liquidity,
                        cache.holdTokenDebt
                    );

                    // Perform v3 swap exact input and update sqrtPriceX96
                    _v3SwapExactInput(
                        v3SwapExactInputParams({
                            fee: params.fee,
                            tokenIn: cache.holdToken,
                            tokenOut: cache.saleToken,
                            amountIn: holdTokenAmountIn,
                            amountOutMinimum: (saleTokenAmountOut * params.slippageBP1000) /
                                Constants.BPS
                        })
                    );
                    // Update the value of sqrtPriceX96 in the cache using the _getCurrentSqrtPriceX96 function
                    cache.sqrtPriceX96 = _getCurrentSqrtPriceX96(
                        params.zeroForSaleToken,
                        cache.saleToken,
                        cache.holdToken,
                        cache.fee
                    );
                    // Calculate the amounts of token0 and token1 for a given liquidity
                    (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                        cache.sqrtPriceX96,
                        TickMath.getSqrtRatioAtTick(cache.tickLower),
                        TickMath.getSqrtRatioAtTick(cache.tickUpper),
                        loan.liquidity
                    );
                }
            }
            // Get the owner of the Nonfungible Position Manager token by its tokenId
            address creditor = underlyingPositionManager.ownerOf(loan.tokenId);
            // Increase liquidity and transfer liquidity owner reward
            _increaseLiquidity(cache.saleToken, cache.holdToken, loan, amount0, amount1);
            uint256 liquidityOwnerReward = FullMath.mulDiv(
                params.totalfeesOwed,
                cache.holdTokenDebt,
                params.totalBorrowedAmount
            ) / Constants.COLLATERAL_BALANCE_PRECISION;

            //@audit-info blacklisted creditor can block all transfers
            //which locks both the collateral and all loans
            //@audit report submitted
            Vault(VAULT_ADDRESS).transferToken(cache.holdToken, creditor, liquidityOwnerReward);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Retrieves the current square root price in X96 representation.
     * @param zeroForA Flag indicating whether to treat the tokenA as the 0th token or not.
     * @param tokenA The address of token A.
     * @param tokenB The address of token B.
     * @param fee The fee associated with the Uniswap V3 pool.
     * @return sqrtPriceX96 The current square root price in X96 representation.
     */
    function _getCurrentSqrtPriceX96(
        bool zeroForA,
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (uint160 sqrtPriceX96) {
        if (!zeroForA) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        address poolAddress = computePoolAddress(tokenA, tokenB, fee);
        (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddress).slot0();
    }

    /**
     * @dev Decreases the liquidity of a position by removing tokens.
     * @param tokenId The ID of the position token.
     * @param liquidity The amount of liquidity to be removed.
     */
    function _decreaseLiquidity(uint256 tokenId, uint128 liquidity) private {
        // Call the decreaseLiquidity function of underlyingPositionManager contract
        // with DecreaseLiquidityParams struct as argument
        (uint256 amount0, uint256 amount1) = underlyingPositionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,

                //@audit-info this uses block.timestamp which is considered a vuln
                //but this is only used behind another timestamp
                //validation so this is fine
                deadline: block.timestamp
            })
        );
        // Check if both amount0 and amount1 are zero after decreasing liquidity
        // If true, revert with InvalidBorrowedLiquidity exception
        if (amount0 == 0 && amount1 == 0) {
            revert InvalidBorrowedLiquidity(tokenId);
        }
        // Call the collect function of underlyingPositionManager contract
        // with CollectParams struct as argument

        //@audit-info remove tokens from position and send them here
        //@audit-info only removes the amount gained from the burn
        (amount0, amount1) = underlyingPositionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: uint128(amount0),
                amount1Max: uint128(amount1)
            })
        );
    }

    /**
     * @dev Increases the liquidity of a position by providing additional tokens.
     * @param saleToken The address of the sale token.
     * @param holdToken The address of the hold token.
     * @param loan An instance of LoanInfo memory struct containing loan details.
     * @param amount0 The amount of token0 to be added to the liquidity.
     * @param amount1 The amount of token1 to be added to the liquidity.
     */
    function _increaseLiquidity(
        address saleToken,
        address holdToken,
        LoanInfo memory loan,
        uint256 amount0,
        uint256 amount1
    ) private {
        // increase if not equal to zero to avoid rounding down the amount of restored liquidity.
        if (amount0 > 0) ++amount0;
        if (amount1 > 0) ++amount1;
        // Call the increaseLiquidity function of underlyingPositionManager contract
        // with IncreaseLiquidityParams struct as argument
        (uint128 restoredLiquidity, , ) = underlyingPositionManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: loan.tokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
        // Check if the restored liquidity is less than the loan liquidity amount
        // If true, revert with InvalidRestoredLiquidity exception
        if (restoredLiquidity < loan.liquidity) {
            // Get the balance of holdToken and saleToken
            (uint256 holdTokentBalance, uint256 saleTokenBalance) = _getPairBalance(
                holdToken,
                saleToken
            );

            revert InvalidRestoredLiquidity(
                loan.tokenId,
                loan.liquidity,
                restoredLiquidity,
                amount0,
                amount1,
                holdTokentBalance,
                saleTokenBalance
            );
        }
    }

    /**
     * @dev Calculates the amount of hold token required for a swap.
     * @param zeroForSaleToken A boolean value indicating whether the token for sale is the 0th token or not.
     * @param tickLower The lower tick of the liquidity range.
     * @param tickUpper The upper tick of the liquidity range.
     * @param sqrtPriceX96 The square root of the price ratio of the sale token to the hold token.
     * @param liquidity The amount of liquidity.
     * @param holdTokenDebt The amount of hold token debt.
     * @return holdTokenAmountIn The amount of hold token needed to provide the specified liquidity.
     * @return amount0 The amount of token0 calculated based on the liquidity.
     * @return amount1 The amount of token1 calculated based on the liquidity.
     */
    function _getHoldTokenAmountIn(
        bool zeroForSaleToken,
        int24 tickLower,
        int24 tickUpper,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint256 holdTokenDebt
    ) private pure returns (uint256 holdTokenAmountIn, uint256 amount0, uint256 amount1) {
        // Call getAmountsForLiquidity function from LiquidityAmounts library
        // to get the amounts of token0 and token1 for a given liquidity position
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
        // Calculate the holdTokenAmountIn based on the zeroForSaleToken flag

        //@audit-issue need more context to understand
        if (zeroForSaleToken) {
            // If zeroForSaleToken is true, check if amount0 is zero
            // If true, holdTokenAmountIn will be zero. Otherwise, it will be holdTokenDebt - amount1
            holdTokenAmountIn = amount0 == 0 ? 0 : holdTokenDebt - amount1;
        } else {
            // If zeroForSaleToken is false, check if amount1 is zero
            // If true, holdTokenAmountIn will be zero. Otherwise, it will be holdTokenDebt - amount0
            holdTokenAmountIn = amount1 == 0 ? 0 : holdTokenDebt - amount0;
        }
    }

    /**
     * @dev Updates the RestoreLiquidityCache struct with data from the underlyingPositionManager contract.
     * @param zeroForSaleToken A boolean value indicating whether the token for sale is the 0th token or not.
     * @param loan The LoanInfo struct containing loan details.
     * @param cache The RestoreLiquidityCache struct to be updated.
     */

    //@audit-issue what is stopping someone from manipulating the price
    //low, take loan, then close for profit?
    //@audit-info if that's not profitable then what is stopping the
    //lender from manipulating the price right before the user
    //takes the loan and fucks them over?
    function _upRestoreLiquidityCache(
        bool zeroForSaleToken,
        LoanInfo memory loan,
        RestoreLiquidityCache memory cache
    ) internal view {
        // Get the positions data from `PositionManager` and store it in the cache variables
        (
            ,
            ,
            cache.saleToken,
            cache.holdToken,
            cache.fee,
            cache.tickLower,
            cache.tickUpper,
            ,
            ,
            ,
            ,

        ) = underlyingPositionManager.positions(loan.tokenId);
        // Swap saleToken and holdToken if zeroForSaleToken is false
        if (!zeroForSaleToken) {
            (cache.saleToken, cache.holdToken) = (cache.holdToken, cache.saleToken);
        }
        // Calculate the holdTokenDebt using
        cache.holdTokenDebt = _getSingleSideRoundUpBorrowedAmount(
            zeroForSaleToken,
            cache.tickLower,
            cache.tickUpper,
            loan.liquidity
        );
        // Calculate the square root price using `_getCurrentSqrtPriceX96` function
        cache.sqrtPriceX96 = _getCurrentSqrtPriceX96(
            zeroForSaleToken,
            cache.saleToken,
            cache.holdToken,
            cache.fee
        );
    }
}
