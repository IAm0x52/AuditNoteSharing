// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;
import "@openzeppelin/contracts/access/Ownable.sol";
import { Constants } from "../libraries/Constants.sol";

abstract contract OwnerSettings is Ownable {
    /**
     * @dev Enum representing various items.
     *
     * @param PLATFORM_FEES_BP The percentage of platform fees in basis points.
     * @param DEFAULT_LIQUIDATION_BONUS The default liquidation bonus.
     * @param DAILY_RATE_OPERATOR The operator for calculating the daily rate.
     * @param LIQUIDATION_BONUS_FOR_TOKEN The liquidation bonus for a specific token.
     */
    enum ITEM {
        PLATFORM_FEES_BP,
        DEFAULT_LIQUIDATION_BONUS,
        DAILY_RATE_OPERATOR,
        LIQUIDATION_BONUS_FOR_TOKEN
    }
    /**
     * @dev Struct representing liquidation parameters.
     *
     * @param bonusBP The bonus in basis points that will be applied during a liquidation.
     * @param minBonusAmount The minimum amount of bonus that can be applied during a liquidation.
     */
    struct Liquidation {
        uint256 bonusBP;
        uint256 minBonusAmount;
    }
    /**
     * @dev Address of the daily rate operator.
     */
    address public dailyRateOperator;
    /**
     * @dev Platform fees in basis points.
     * 2000 BP represents a 20% fee on the daily rate.
     */
    uint256 public platformFeesBP = 2000;
    /**
     * @dev Default liquidation bonus in basis points.
     * 69 BP represents a 0.69% bonus per extracted liquidity.
     */
    uint256 public dafaultLiquidationBonusBP = 69;
    /**
     * @dev Mapping to store liquidation bonuses for each token address.
     * The keys are token addresses and values are instances of the `Liquidation` struct.
     */
    mapping(address => Liquidation) public liquidationBonusForToken;

    error InvalidSettingsValue(uint256 value);

    constructor() {
        dailyRateOperator = msg.sender;
    }

    /**
     * @notice This external function is used to update the settings for a particular item. The function requires two parameters: `_item`,
     * which is the item to be updated, and `values`, which is an array of values containing the new settings.
     * Only the owner of the contract has the permission to call this function.
     * @dev Can only be called by the owner of the contract.
     * @param _item The item to update the settings for.
     * @param values An array of values containing the new settings.
     */
    function updateSettings(ITEM _item, uint256[] calldata values) external onlyOwner {
        if (_item == ITEM.LIQUIDATION_BONUS_FOR_TOKEN) {
            require(values.length == 3);
            if (values[1] > Constants.MAX_LIQUIDATION_BONUS) {
                revert InvalidSettingsValue(values[1]);
            }
            if (values[2] == 0) {
                revert InvalidSettingsValue(0);
            }
            liquidationBonusForToken[address(uint160(values[0]))] = Liquidation(
                values[1],
                values[2]
            );
        } else if (_item == ITEM.DAILY_RATE_OPERATOR) {
            require(values.length == 1);
            dailyRateOperator = address(uint160(values[0]));
        } else {
            if (_item == ITEM.PLATFORM_FEES_BP) {
                require(values.length == 1);
                if (values[0] > Constants.MAX_PLATFORM_FEE) {
                    revert InvalidSettingsValue(values[0]);
                }
                platformFeesBP = values[0];
            } else if (_item == ITEM.DEFAULT_LIQUIDATION_BONUS) {
                require(values.length == 1);
                if (values[0] > Constants.MAX_LIQUIDATION_BONUS) {
                    revert InvalidSettingsValue(values[0]);
                }
                dafaultLiquidationBonusBP = values[0];
            }
        }
    }
}
