// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "../../../../contracts/abstract/ApproveSwapAndPay.sol";
import "../../../../contracts/libraries/Keys.sol";

contract $ApproveSwapAndPay is ApproveSwapAndPay {
    using { Keys.removeKey, Keys.addKeyIfNotExists } for bytes32[];

    bytes32 public constant __hh_exposed_bytecode_marker = "hardhat-exposed";
    bytes32[] self;

    event return$_patchAmountsAndCallSwap(uint256 amountOut);

    event return$_v3SwapExactInput(uint256 amountOut);

    constructor(
        address _UNDERLYING_V3_FACTORY_ADDRESS,
        bytes32 _UNDERLYING_V3_POOL_INIT_CODE_HASH
    )
        payable
        ApproveSwapAndPay(_UNDERLYING_V3_FACTORY_ADDRESS, _UNDERLYING_V3_POOL_INIT_CODE_HASH)
    {}

    function $MIN_SQRT_RATIO() external pure returns (uint160) {
        return MIN_SQRT_RATIO;
    }

    function $MAX_SQRT_RATIO() external pure returns (uint160) {
        return MAX_SQRT_RATIO;
    }

    function $_removeKey(bytes32 key) external {
        self.removeKey(key);
    }

    function $_addKeyIfNotExists(bytes32 key) external {
        self.addKeyIfNotExists(key);
    }

    function $getSelf() external view returns (bytes32[] memory) {
        return self;
    }

    function $_computePairKey(
        address saleToken,
        address holdToken
    ) external pure returns (bytes32) {
        return Keys.computePairKey(saleToken, holdToken);
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

    function $setSwapCallToWhitelist(
        address swapTarget,
        bytes4 funcSelector,
        bool isAllowed
    ) external {
        whitelistedCall[swapTarget][funcSelector] = isAllowed;
    }

    receive() external payable {}
}
