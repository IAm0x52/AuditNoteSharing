// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IQuoterV2.sol";

contract AggregatorMock {
    IQuoterV2 public immutable underlyingQuoterV2;

    constructor(address _underlyingQuoterV2) {
        underlyingQuoterV2 = IQuoterV2(_underlyingQuoterV2);
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, ) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success, "AggregatorMock: safeTransfer failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) private {
        (bool success, ) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        require(success, "AggregatorMock: safeTransferFrom failed");
    }

    function nonWhitelistedSwap(bytes calldata wrappedCallData) external {
        _swap(wrappedCallData);
    }

    function swap(bytes calldata wrappedCallData) external {
        _swap(wrappedCallData);
    }

    function _swap(bytes calldata wrappedCallData) internal {
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin) = abi.decode(
            wrappedCallData,
            (address, address, uint256, uint256)
        );
        require(tokenIn != tokenOut, "TE");

        (uint256 amountOut, , , ) = underlyingQuoterV2.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                fee: 500,
                sqrtPriceLimitX96: 0
            })
        );

        require(amountOut >= amountOutMin, "AggregatorMock: price slippage check");
        _safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        _safeTransfer(tokenOut, msg.sender, amountOut);
    }
}
