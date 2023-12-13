// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "../../../../contracts/abstract/LiquidityManager.sol";

contract $LiquidityManager is LiquidityManager {
    bytes32 public constant __hh_exposed_bytecode_marker = "hardhat-exposed";

    event return$_extractLiquidity(uint256 borrowedAmount);

    event return$_patchAmountsAndCallSwap(uint256 amountOut);

    event return$_v3SwapExactInput(uint256 amountOut);

    constructor(
        address _underlyingPositionManagerAddress,
        address _underlyingQuoterV2,
        address _underlyingV3Factory,
        bytes32 _underlyingV3PoolInitCodeHash
    )
        payable
        LiquidityManager(
            _underlyingPositionManagerAddress,
            _underlyingQuoterV2,
            _underlyingV3Factory,
            _underlyingV3PoolInitCodeHash
        )
    {}

    function $MIN_SQRT_RATIO() external pure returns (uint160) {
        return MIN_SQRT_RATIO;
    }

    function $MAX_SQRT_RATIO() external pure returns (uint160) {
        return MAX_SQRT_RATIO;
    }

    function $_extractLiquidity(
        bool zeroForSaleToken,
        address token0,
        address token1,
        LoanInfo[] calldata loans
    ) external returns (uint256 borrowedAmount) {
        (borrowedAmount) = super._extractLiquidity(zeroForSaleToken, token0, token1, loans);
        emit return$_extractLiquidity(borrowedAmount);
    }

    function $_restoreLiquidity(
        RestoreLiquidityParams calldata params,
        SwapParams calldata externalSwap,
        LoanInfo[] calldata loans
    ) external {
        super._restoreLiquidity(params, externalSwap, loans);
    }

    function $_maxApproveIfNecessary(address token, address spender, uint256 amount) external {
        super._maxApproveIfNecessary(token, spender, amount);
    }

    function $_getBalance(address token) external view returns (uint256 balance) {
        (balance) = super._getBalance(token);
    }

    function $_getPairBalance(
        address tokenA,
        address tokenB
    ) external view returns (uint256 balanceA, uint256 balanceB) {
        (balanceA, balanceB) = super._getPairBalance(tokenA, tokenB);
    }

    function $_patchAmountsAndCallSwap(
        address tokenIn,
        address tokenOut,
        SwapParams calldata externalSwap,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 amountOut) {
        (amountOut) = super._patchAmountsAndCallSwap(
            tokenIn,
            tokenOut,
            externalSwap,
            amountIn,
            amountOutMin
        );
        emit return$_patchAmountsAndCallSwap(amountOut);
    }

    function $_pay(address token, address payer, address recipient, uint256 value) external {
        super._pay(token, payer, recipient, value);
    }

    function $_v3SwapExactInput(
        v3SwapExactInputParams calldata params
    ) external returns (uint256 amountOut) {
        (amountOut) = super._v3SwapExactInput(params);
        emit return$_v3SwapExactInput(amountOut);
    }

    receive() external payable {}
}
