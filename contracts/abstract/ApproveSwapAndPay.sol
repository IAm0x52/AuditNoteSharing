// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { SafeCast } from "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import "../libraries/ExternalCall.sol";
import "../libraries/ErrLib.sol";

abstract contract ApproveSwapAndPay {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using { ExternalCall._patchAmountAndCall } for address;
    using { ExternalCall._readFirstBytes4 } for bytes;
    using { ErrLib.revertError } for bool;

    /// @notice Struct representing the parameters for a Uniswap V3 exact input swap.
    struct v3SwapExactInputParams {
        /// @dev The fee tier to be used for the swap.
        uint24 fee;
        /// @dev The address of the token to be swapped from.
        address tokenIn;
        /// @dev The address of the token to be swapped to.
        address tokenOut;
        /// @dev The amount of `tokenIn` to be swapped.
        uint256 amountIn;
        /// @dev The minimum amount of `tokenOut` expected to receive from the swap.
        uint256 amountOutMinimum;
    }

    /// @notice Struct to hold parameters for swapping tokens
    struct SwapParams {
        /// @notice Address of the aggregator's router
        address swapTarget;
        /// @notice The index in the `swapData` array where the swap amount in is stored
        uint256 swapAmountInDataIndex;
        /// @notice The maximum gas limit for the swap call
        uint256 maxGasForCall;
        /// @notice The aggregator's data that stores paths and amounts for swapping through
        bytes swapData;
    }

    //@audit-ok pulled directly from uni library
    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;

    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    address public immutable UNDERLYING_V3_FACTORY_ADDRESS;
    bytes32 public immutable UNDERLYING_V3_POOL_INIT_CODE_HASH;

    ///     swapTarget   => (func.selector => is allowed)
    mapping(address => mapping(bytes4 => bool)) public whitelistedCall;

    error SwapSlippageCheckError(uint256 expectedOut, uint256 receivedOut);

    constructor(
        address _UNDERLYING_V3_FACTORY_ADDRESS,
        bytes32 _UNDERLYING_V3_POOL_INIT_CODE_HASH
    ) {
        UNDERLYING_V3_FACTORY_ADDRESS = _UNDERLYING_V3_FACTORY_ADDRESS;
        UNDERLYING_V3_POOL_INIT_CODE_HASH = _UNDERLYING_V3_POOL_INIT_CODE_HASH;
    }

    /**
     * @dev This internal function attempts to approve a specific amount of tokens for a spender.
     * It performs a call to the `approve` function on the token contract using the provided parameters,
     * and returns a boolean indicating whether the approval was successful or not.
     * @param token The address of the token contract.
     * @param spender The address of the spender.
     * @param amount The amount of tokens to be approved.
     * @return A boolean indicating whether the approval was successful or not.
     */

    //@audit-ok nothign to see here
    function _tryApprove(address token, address spender, uint256 amount) private returns (bool) {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    /**
     * @dev This internal function ensures that the allowance for a spender is at least the specified amount.
     * If the current allowance is less than the specified amount, it attempts to approve the maximum possible value,
     * and if that fails, it retries with the maximum possible value minus one. If both attempts fail,
     * it reverts with an error indicating that the approval did not succeed.
     * @param token The address of the token contract.
     * @param spender The address of the spender.
     * @param amount The minimum required allowance.
     */

    //@audit-info what
    function _maxApproveIfNecessary(address token, address spender, uint256 amount) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            if (!_tryApprove(token, spender, type(uint256).max)) {
                if (!_tryApprove(token, spender, type(uint256).max - 1)) {
                    require(_tryApprove(token, spender, 0));
                    if (!_tryApprove(token, spender, type(uint256).max)) {
                        if (!_tryApprove(token, spender, type(uint256).max - 1)) {
                            true.revertError(ErrLib.ErrorCode.ERC20_APPROVE_DID_NOT_SUCCEED);
                        }
                    }
                }
            }
        }
    }

    /**
     * @dev This internal view function retrieves the balance of the contract for a specific token.
     * It performs a staticcall to the `balanceOf` function on the token contract using the provided parameter,
     * and returns the balance as a uint256 value.
     * @param token The address of the token contract.
     * @return balance The balance of the contract for the specified token.
     */

    //@audit-ok fine
    function _getBalance(address token) internal view returns (uint256 balance) {
        bytes memory callData = abi.encodeWithSelector(IERC20.balanceOf.selector, address(this));
        (bool success, bytes memory data) = token.staticcall(callData);
        require(success && data.length >= 32);
        balance = abi.decode(data, (uint256));
    }

    /**
     * @dev Retrieves the balance of two tokens in the contract.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return balanceA The balance of the first token in the contract.
     * @return balanceB The balance of the second token in the contract.
     */

    //@audit-ok also fine
    function _getPairBalance(
        address tokenA,
        address tokenB
    ) internal view returns (uint256 balanceA, uint256 balanceB) {
        balanceA = _getBalance(tokenA);
        balanceB = _getBalance(tokenB);
    }

    /**
     * @dev Executes a swap between two tokens using an external contract.
     * @param tokenIn The address of the token to be swapped.
     * @param tokenOut The address of the token to receive in the swap.
     * @param externalSwap The swap parameters from the external contract.
     * @param amountIn The amount of `tokenIn` to be swapped.
     * @param amountOutMin The minimum amount of `tokenOut` expected to receive from the swap.
     * @return amountOut The actual amount of `tokenOut` received from the swap.
     * @notice This function will revert if the swap target is not approved or the resulting amountOut
     * is zero or below the specified minimum amountOut.
     */
    function _patchAmountsAndCallSwap(
        address tokenIn,
        address tokenOut,
        SwapParams calldata externalSwap,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        bytes4 funcSelector = externalSwap.swapData._readFirstBytes4();
        // Verifying if the swap target is whitelisted for the specified function selector

        //@audit-info revert if target and selector haven't been whitelisted
        (!whitelistedCall[externalSwap.swapTarget][funcSelector]).revertError(
            ErrLib.ErrorCode.SWAP_TARGET_NOT_APPROVED
        );
        // Maximizing approval if necessary
        _maxApproveIfNecessary(tokenIn, externalSwap.swapTarget, amountIn);
        uint256 balanceOutBefore = _getBalance(tokenOut);
        // Patching the amount and calling the external swap
        externalSwap.swapTarget._patchAmountAndCall(
            externalSwap.swapData,
            externalSwap.maxGasForCall,
            externalSwap.swapAmountInDataIndex,
            amountIn
        );
        // Calculating the actual amount of output tokens received
        amountOut = _getBalance(tokenOut) - balanceOutBefore;
        // Checking if the received amount satisfies the minimum requirement
        if (amountOut == 0 || amountOut < amountOutMin) {
            revert SwapSlippageCheckError(amountOutMin, amountOut);
        }
    }

    /**
     * @dev Transfers a specified amount of tokens from the `payer` to the `recipient`.
     * @param token The address of the token to be transferred.
     * @param payer The address from which the tokens will be transferred.
     * @param recipient The address that will receive the tokens.
     * @param value The amount of tokens to be transferred.
     * @notice If the specified `value` is greater than zero, this function will transfer the tokens either by calling `safeTransfer`
     * if the `payer` is equal to `address(this)`, or by calling `safeTransferFrom` otherwise.
     */
    function _pay(address token, address payer, address recipient, uint256 value) internal {
        if (value > 0) {
            if (payer == address(this)) {
                IERC20(token).safeTransfer(recipient, value);
            } else {
                IERC20(token).safeTransferFrom(payer, recipient, value);
            }
        }
    }

    /**
     * @dev Performs a token swap using Uniswap V3 with exact input.
     * @param params The struct containing all swap parameters.
     * @return amountOut The amount of tokens received as output from the swap.
     * @notice This internal function swaps the exact amount of `params.amountIn` tokens from `params.tokenIn` to `params.tokenOut`.
     * The swapped amount is calculated based on the current pool ratio between `params.tokenIn` and `params.tokenOut`.
     * If the resulting `amountOut` is less than `params.amountOutMinimum`, the function will revert with a `SwapSlippageCheckError`
     * indicating the minimum expected amount was not met.
     */
    function _v3SwapExactInput(
        v3SwapExactInputParams memory params
    ) internal returns (uint256 amountOut) {
        // Determine if tokenIn has a 0th token
        bool zeroForTokenIn = params.tokenIn < params.tokenOut;
        // Compute the address of the Uniswap V3 pool based on tokenIn, tokenOut, and fee
        // Call the swap function on the Uniswap V3 pool contract
        (int256 amount0Delta, int256 amount1Delta) = IUniswapV3Pool(
            computePoolAddress(params.tokenIn, params.tokenOut, params.fee)
        ).swap(
                address(this), //recipient
                zeroForTokenIn,
                params.amountIn.toInt256(),
                (zeroForTokenIn ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1),
                abi.encode(params.fee, params.tokenIn, params.tokenOut)
            );
        // Calculate the actual amount of output tokens received
        amountOut = uint256(-(zeroForTokenIn ? amount1Delta : amount0Delta));
        // Check if the received amount satisfies the minimum requirement
        if (amountOut < params.amountOutMinimum) {
            revert SwapSlippageCheckError(params.amountOutMinimum, amountOut);
        }
    }

    /**
     * @dev Callback function invoked by Uniswap V3 swap.
     *
     * This function is called when a swap is executed on a Uniswap V3 pool. It performs the necessary validations
     * and payment processing.
     *
     * Requirements:
     * - The swap must not entirely fall within 0-liquidity regions, as it is not supported.
     * - The caller must be the expected Uniswap V3 pool contract.
     *
     * @param amount0Delta The change in token0 balance resulting from the swap.
     * @param amount1Delta The change in token1 balance resulting from the swap.
     * @param data Additional data required for processing the swap, encoded as `(uint24, address, address)`.
     */

    //@audit-ok I don't see any other issue here

    //@audit-issue is it possible for this to be called by anything else?
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        (amount0Delta <= 0 && amount1Delta <= 0).revertError(ErrLib.ErrorCode.INVALID_SWAP); // swaps entirely within 0-liquidity regions are not supported

        (uint24 fee, address tokenIn, address tokenOut) = abi.decode(
            data,
            (uint24, address, address)
        );

        //@audit-info if this contract doesn't contain funds normally then nothing
        //to see here. It doesn't
        (computePoolAddress(tokenIn, tokenOut, fee) != msg.sender).revertError(
            ErrLib.ErrorCode.INVALID_CALLER
        );
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        _pay(tokenIn, address(this), msg.sender, amountToPay);
    }

    /**
     * @dev Computes the address of a Uniswap V3 pool based on the provided parameters.
     *
     * This function calculates the address of a Uniswap V3 pool contract using the token addresses and fee.
     * It follows the same logic as Uniswap's pool initialization process.
     *
     * @param tokenA The address of one of the tokens in the pair.
     * @param tokenB The address of the other token in the pair.
     * @param fee The fee level of the pool.
     * @return pool The computed address of the Uniswap V3 pool.
     */

    //@audit-info not compatible with with ZkSync
    //@audit report submitted
    function computePoolAddress(
        address tokenA,
        address tokenB,
        uint24 fee
    ) public view returns (address pool) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            UNDERLYING_V3_FACTORY_ADDRESS,
                            keccak256(abi.encode(tokenA, tokenB, fee)),
                            UNDERLYING_V3_POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
