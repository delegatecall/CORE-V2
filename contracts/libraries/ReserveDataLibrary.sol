// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol';

import '../libraries/WadRayMath.sol';

/**
 * @title ReserveDataLibrary library
 * @author Aave
 * @notice Defines the data structures of the reserves and the user data
 **/
library ReserveDataLibrary {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    struct ReserveData {
        /**
         * @dev refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
         **/
        //the liquidity index. Expressed in ray
        uint256 lastLiquidityCumulativeIndex;
        //the current supply rate. Expressed in ray
        uint256 currentLiquidityRate;
        //the total borrows of the reserve at a variable rate. Expressed in the currency decimals
        uint256 totalBorrowsVariable;
        //the current variable borrow rate. Expressed in ray
        uint256 currentVariableBorrowRate;
        //variable borrow index. Expressed in ray
        uint256 lastVariableBorrowCumulativeIndex;
        //the ltv of the reserve. Expressed in percentage (0-100)
        uint256 baseLTVasCollateral;
        //the liquidation threshold of the reserve. Expressed in percentage (0-100)
        uint256 liquidationThreshold;
        //the liquidation bonus of the reserve. Expressed in percentage
        uint256 liquidationBonus;
        //the decimals of the reserve asset
        uint256 decimals;
        /**
         * @dev address of the CToken representing the asset
         **/
        address overlyingTokenAddress;
        uint40 lastUpdateTimestamp;
        // borrowingEnabled = true means users can borrow from this reserve
        bool borrowingEnabled;
        // usageAsCollateralEnabled = true means users can use this reserve as collateral
        bool usageAsCollateralEnabled;
        // isActive = true means the reserve has been activated and properly configured
        bool isActive;
        // isFreezed = true means the reserve only allows repays and redeems, but not deposits, new borrowings or rate swap
        bool isFreezed;
    }

    /**
     * @dev returns the ongoing normalized income for the reserve.
     * a value of 1e27 means there is no income. As time passes, the income is accrued.
     * A value of 2*1e27 means that the income of the reserve is double the initial amount.
     * @param _reserve the reserve object
     * @return the normalized income. expressed in ray
     **/
    function getNormalizedIncome(ReserveData storage _reserve) internal view returns (uint256) {
        uint256 cumulated = calculateLinearInterest(_reserve.currentLiquidityRate, _reserve.lastUpdateTimestamp).rayMul(
            _reserve.lastLiquidityCumulativeIndex
        );

        return cumulated;
    }

    /**
     * @dev Updates the liquidity cumulative index Ci and variable borrow cumulative index Bvc. Refer to the whitepaper for
     * a formal specification.
     * @param _self the reserve object
     **/
    function updateCumulativeIndexes(ReserveData storage _self) internal {
        uint256 totalBorrows = getTotalBorrows(_self);

        if (totalBorrows > 0) {
            //only cumulating if there is any income being produced
            uint256 cumulatedLiquidityInterest = calculateLinearInterest(
                _self.currentLiquidityRate,
                _self.lastUpdateTimestamp
            );

            _self.lastLiquidityCumulativeIndex = cumulatedLiquidityInterest.rayMul(_self.lastLiquidityCumulativeIndex);

            uint256 cumulatedVariableBorrowInterest = calculateCompoundedInterest(
                _self.currentVariableBorrowRate,
                _self.lastUpdateTimestamp
            );
            _self.lastVariableBorrowCumulativeIndex = cumulatedVariableBorrowInterest.rayMul(
                _self.lastVariableBorrowCumulativeIndex
            );
        }
    }

    /**
     * @dev accumulates a predefined amount of asset to the reserve as a fixed, one time income. Used for example to accumulate
     * the flashloan fee to the reserve, and spread it through the depositors.
     * @param _self the reserve object
     * @param _totalLiquidity the total liquidity available in the reserve
     * @param _amount the amount to accomulate
     **/
    function cumulateToLiquidityIndex(
        ReserveData storage _self,
        uint256 _totalLiquidity,
        uint256 _amount
    ) internal {
        uint256 amountToLiquidityRatio = _amount.wadToRay().rayDiv(_totalLiquidity.wadToRay());

        uint256 cumulatedLiquidity = amountToLiquidityRatio.add(WadRayMath.ray());

        _self.lastLiquidityCumulativeIndex = cumulatedLiquidity.rayMul(_self.lastLiquidityCumulativeIndex);
    }

    /**
     * @dev initializes a reserve
     * @param _self the reserve object
     * @param _overlyingTokenAddress the address of the overlying atoken contract
     * @param _decimals the number of decimals of the underlying asset
     **/
    function init(
        ReserveData storage _self,
        address _overlyingTokenAddress,
        uint256 _decimals
    ) external {
        require(_self.overlyingTokenAddress == address(0), 'Reserve has already been initialized');

        if (_self.lastLiquidityCumulativeIndex == 0) {
            //if the reserve has not been initialized yet
            _self.lastLiquidityCumulativeIndex = WadRayMath.ray();
        }

        if (_self.lastVariableBorrowCumulativeIndex == 0) {
            _self.lastVariableBorrowCumulativeIndex = WadRayMath.ray();
        }

        _self.overlyingTokenAddress = _overlyingTokenAddress;
        _self.decimals = _decimals;
        _self.currentVariableBorrowRate = WadRayMath.ray();
        _self.isActive = true;
        _self.isFreezed = false;
    }

    /**
     * @dev enables borrowing on a reserve
     * @param _self the reserve object
     * @param _stableBorrowRateEnabled true if the stable borrow rate must be enabled by default, false otherwise
     **/
    function enableBorrowing(ReserveData storage _self, bool _stableBorrowRateEnabled) external {
        require(_self.borrowingEnabled == false, 'Reserve is already enabled');

        _self.borrowingEnabled = true;
    }

    /**
     * @dev disables borrowing on a reserve
     * @param _self the reserve object
     **/
    function disableBorrowing(ReserveData storage _self) external {
        _self.borrowingEnabled = false;
    }

    /**
     * @dev enables a reserve to be used as collateral
     * @param _self the reserve object
     * @param _baseLTVasCollateral the loan to value of the asset when used as collateral
     * @param _liquidationThreshold the threshold at which loans using this asset as collateral will be considered undercollateralized
     * @param _liquidationBonus the bonus liquidators receive to liquidate this asset
     **/
    function enableAsCollateral(
        ReserveData storage _self,
        uint256 _baseLTVasCollateral,
        uint256 _liquidationThreshold,
        uint256 _liquidationBonus
    ) external {
        require(_self.usageAsCollateralEnabled == false, 'Reserve is already enabled as collateral');

        _self.usageAsCollateralEnabled = true;
        _self.baseLTVasCollateral = _baseLTVasCollateral;
        _self.liquidationThreshold = _liquidationThreshold;
        _self.liquidationBonus = _liquidationBonus;

        if (_self.lastLiquidityCumulativeIndex == 0) _self.lastLiquidityCumulativeIndex = WadRayMath.ray();
    }

    /**
     * @dev disables a reserve as collateral
     * @param _self the reserve object
     **/
    function disableAsCollateral(ReserveData storage _self) external {
        _self.usageAsCollateralEnabled = false;
    }

    /**
     * @dev increases the total borrows at a variable rate
     * @param _reserve the reserve object
     * @param _amount the amount to add to the total borrows variable
     **/
    function increaseTotalBorrowsVariable(ReserveData storage _reserve, uint256 _amount) internal {
        _reserve.totalBorrowsVariable = _reserve.totalBorrowsVariable.add(_amount);
    }

    /**
     * @dev decreases the total borrows at a variable rate
     * @param _reserve the reserve object
     * @param _amount the amount to substract to the total borrows variable
     **/
    function decreaseTotalBorrowsVariable(ReserveData storage _reserve, uint256 _amount) internal {
        require(
            _reserve.totalBorrowsVariable >= _amount,
            'The amount that is being subtracted from the variable total borrows is incorrect'
        );
        _reserve.totalBorrowsVariable = _reserve.totalBorrowsVariable.sub(_amount);
    }

    /**
     * @dev function to calculate the interest using a linear interest rate formula
     * @param _rate the interest rate, in ray
     * @param _lastUpdateTimestamp the timestamp of the last update of the interest
     * @return the interest rate linearly accumulated during the timeDelta, in ray
     **/

    function calculateLinearInterest(uint256 _rate, uint40 _lastUpdateTimestamp) internal view returns (uint256) {
        //solium-disable-next-line
        uint256 timeDifference = block.timestamp.sub(uint256(_lastUpdateTimestamp));

        uint256 timeDelta = timeDifference.wadToRay().rayDiv(SECONDS_PER_YEAR.wadToRay());

        return _rate.rayMul(timeDelta).add(WadRayMath.ray());
    }

    /**
     * @dev function to calculate the interest using a compounded interest rate formula
     * @param _rate the interest rate, in ray
     * @param _lastUpdateTimestamp the timestamp of the last update of the interest
     * @return the interest rate compounded during the timeDelta, in ray
     **/
    function calculateCompoundedInterest(uint256 _rate, uint40 _lastUpdateTimestamp) internal view returns (uint256) {
        //solium-disable-next-line
        uint256 timeDifference = block.timestamp.sub(uint256(_lastUpdateTimestamp));

        uint256 ratePerSecond = _rate.div(SECONDS_PER_YEAR);

        return ratePerSecond.add(WadRayMath.ray()).rayPow(timeDifference);
    }

    /**
     * @dev returns the total borrows on the reserve
     * @param _self the reserve object
     * @return the total borrows (stable + variable)
     **/
    function getTotalBorrows(ReserveData storage _self) internal view returns (uint256) {
        return _self.totalBorrowsVariable;
    }
}
