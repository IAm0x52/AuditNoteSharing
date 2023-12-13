// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20FailApprove is ERC20 {
    constructor(string memory _name, string memory _shortName) ERC20(_name, _shortName) {}

    function approve(address spender, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        if (
            (spender == address(1) && amount == type(uint256).max) ||
            (spender == address(2) && amount == type(uint256).max - 1) ||
            (amount == 0 && spender != address(3))
        ) {
            _approve(owner, spender, amount);
            return true;
        } else {
            return false;
        }
    }
}
