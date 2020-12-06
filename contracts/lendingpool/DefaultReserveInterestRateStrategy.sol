// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '../interfaces/IReserveInterestRateStrategy.sol';
import '../libraries/WadRayMath.sol';
import '../configuration/LendingPoolAddressesProvider.sol';
import './LendingPoolCore.sol';

import '@openzeppelin/contracts/math/SafeMath.sol';

contract DefaultReserveInterestRateStrategy is IReserveInterestRateStrategy {
    using WadRayMath for uint256;
    using SafeMath for uint256;

    uint256 public constant OPTIMAL_UTILIZATION_RATE = 0.8 * 1e27;

    uint256 public constant EXCESS_UTILIZATION_RATE = 0.2 * 1e27;

    LendingPoolAddressesProvider public addressesProvider;

    //base variable borrow rate when Utilization rate = 0. Expressed in ray
    uint256 public baseVariableBorrowRate;

    //slope of the variable interest curve when utilization rate > 0 and <= OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 public variableRateSlope1;

    //slope of the variable interest curve when utilization rate > OPTIMAL_UTILIZATION_RATE. Expressed in ray
    uint256 public variableRateSlope2;

    address public reserve;

    constructor(
        address _reserve,
        LendingPoolAddressesProvider _provider,
        uint256 _baseVariableBorrowRate,
        uint256 _variableRateSlope1,
        uint256 _variableRateSlope2,
        uint256 _stableRateSlope1,
        uint256 _stableRateSlope2
    ) public {
        addressesProvider = _provider;
        baseVariableBorrowRate = _baseVariableBorrowRate;
        variableRateSlope1 = _variableRateSlope1;
        variableRateSlope2 = _variableRateSlope2;
        reserve = _reserve;
    }

    /**
    @dev accessors
     */

    function getBaseVariableBorrowRate() external override view returns (uint256) {
        return baseVariableBorrowRate;
    }

    function getVariableRateSlope1() external view returns (uint256) {
        return variableRateSlope1;
    }

    function getVariableRateSlope2() external view returns (uint256) {
        return variableRateSlope2;
    }

    function calculateInterestRates(
        address _reserve,
        uint256 _availableLiquidity,
        uint256 _totalBorrowsVariable,
        uint256 _averageStableBorrowRate
    ) external override view returns (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate) {
        uint256 totalBorrows = _totalBorrowsVariable;

        uint256 utilizationRate = (totalBorrows == 0 && _availableLiquidity == 0)
            ? 0
            : totalBorrows.rayDiv(_availableLiquidity.add(totalBorrows));

        if (utilizationRate > OPTIMAL_UTILIZATION_RATE) {
            uint256 excessUtilizationRateRatio = utilizationRate.sub(OPTIMAL_UTILIZATION_RATE).rayDiv(
                EXCESS_UTILIZATION_RATE
            );

            currentVariableBorrowRate = baseVariableBorrowRate.add(variableRateSlope1).add(
                variableRateSlope2.rayMul(excessUtilizationRateRatio)
            );
        } else {
            currentVariableBorrowRate = baseVariableBorrowRate.add(
                utilizationRate.rayDiv(OPTIMAL_UTILIZATION_RATE).rayMul(variableRateSlope1)
            );
        }

        currentLiquidityRate = getOverallBorrowRateInternal(
            _totalBorrowsVariable,
            currentVariableBorrowRate,
            _averageStableBorrowRate
        )
            .rayMul(utilizationRate);
    }

    function getOverallBorrowRateInternal(
        uint256 _totalBorrowsVariable,
        uint256 _currentVariableBorrowRate,
        uint256 _currentAverageStableBorrowRate
    ) internal pure returns (uint256) {
        uint256 totalBorrows = _totalBorrowsVariable;

        if (totalBorrows == 0) return 0;

        uint256 weightedVariableRate = _totalBorrowsVariable.wadToRay().rayMul(_currentVariableBorrowRate);

        uint256 overallBorrowRate = weightedVariableRate.rayDiv(totalBorrows.wadToRay());

        return overallBorrowRate;
    }
}
