// SPDX-License-Identifier: GPL-2.0-or-later

//@audit-info this uses a solidity version that isn't supported by some rollups (OP for sure)
//@audit report submitted
pragma solidity 0.8.21;
import "@openzeppelin/contracts/utils/Arrays.sol";

library Keys {
    using Arrays for bytes32[];

    /**
     * @dev Adds a key to the array if it does not already exist.
     * @param self The storage array to check and modify.
     * @param key The key to add to the array.
     */

    //@audit-ok works fine
    function addKeyIfNotExists(bytes32[] storage self, bytes32 key) internal {
        uint256 length = self.length;
        for (uint256 i; i < length; ) {
            //@audit-info return if already exists
            if (self.unsafeAccess(i).value == key) {
                return;
            }
            unchecked {
                ++i;
            }
        }
        //@audit-info add key if it doesn't exist
        self.push(key);
    }

    /**
     * @dev Removes a key from the array if it exists.
     * @param self The storage array to check and modify.
     * @param key The key to remove from the array.
     */
    
    //@audit-ok can't find any way to break this
    function removeKey(bytes32[] storage self, bytes32 key) internal {
        uint256 length = self.length;
        for (uint256 i; i < length; ) {
            if (self.unsafeAccess(i).value == key) {
                //@audit-info swap and pop
                self.unsafeAccess(i).value = self.unsafeAccess(length - 1).value;
                self.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Computes the borrowing key based on the borrower's address, sale token address, and hold token address.
     * @param borrower The address of the borrower.
     * @param saleToken The address of the sale token.
     * @param holdToken The address of the hold token.
     * @return The computed borrowing key as a bytes32 value.
     */

    //@audit-ok this is fine. They use packed but there is no
    //variable length vars so this can't collide
    function computeBorrowingKey(
        address borrower,
        address saleToken,
        address holdToken
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(borrower, saleToken, holdToken));
    }

    /**
     * @dev Computes the pair key based on the sale token address and hold token address.
     * @param saleToken The address of the sale token.
     * @param holdToken The address of the hold token.
     * @return The computed pair key as a bytes32 value.
     */

    //@audit-ok same as above
    function computePairKey(address saleToken, address holdToken) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(saleToken, holdToken));
    }
}
