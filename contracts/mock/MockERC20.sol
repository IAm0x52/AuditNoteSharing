// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _shortName) ERC20(_name, _shortName) {
        _mint(msg.sender, 1e24);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
