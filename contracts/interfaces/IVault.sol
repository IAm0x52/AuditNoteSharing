// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

// Interface for the Vault contract
interface IVault {
    // Function to transfer tokens from the vault to a specified address
    function transferToken(address _token, address _to, uint256 _amount) external;

    // Function to get the balances of multiple tokens
    function getBalances(
        address[] calldata tokens
    ) external view returns (uint256[] memory balances);
}
