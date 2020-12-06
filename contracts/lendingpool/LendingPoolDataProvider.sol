// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts/math/SafeMath.sol';

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import '../libraries/CoreLibrary.sol';
import '../configuration/LendingPoolAddressesProvider.sol';
import '../libraries/WadRayMath.sol';
import '../interfaces/IPriceOracle.sol';
import '../tokenization/CToken.sol';

import './LendingPoolCore.sol';

contract LendingPoolDataProvider is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    LendingPoolCore public core;
    LendingPoolAddressesProvider public addressesProvider;

    /**
     * @dev specifies the health factor threshold at which the user position is liquidated.
     * 1e18 by default, if the health factor drops below 1e18, the loan can be liquidated.
     **/
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

    uint256 public constant DATA_PROVIDER_REVISION = 0x1;

    function getRevision() internal pure returns (uint256) {
        return DATA_PROVIDER_REVISION;
    }

    function initialize(LendingPoolAddressesProvider _addressesProvider) public initializer {
        addressesProvider = _addressesProvider;
        core = LendingPoolCore(_addressesProvider.getLendingPoolCore());
    }

    struct UserGlobalDataLocalVars {
        uint256 reserveUnitPrice;
        uint256 tokenUnit;
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 reserveDecimals;
        uint256 baseLtv;
        uint256 liquidationThreshold;
        uint256 originationFee;
        bool usageAsCollateralEnabled;
        bool userUsesReserveAsCollateral;
        address currentReserve;
    }

    function calculateUserGlobalData(address _user)
        public
        view
        returns (
            uint256 totalLiquidityBalanceETH,
            uint256 totalCollateralBalanceETH,
            uint256 totalBorrowBalanceETH,
            uint256 totalFeesETH,
            uint256 currentLtv,
            uint256 currentLiquidationThreshold,
            uint256 healthFactor,
            bool healthFactorBelowThreshold
        )
    {
        IPriceOracle oracle = IPriceOracle(addressesProvider.getPriceOracle());

        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        UserGlobalDataLocalVars memory vars;

        address[] memory reserves = core.getReserves();

        for (uint256 i = 0; i < reserves.length; i++) {
            vars.currentReserve = reserves[i];

            (
                vars.compoundedLiquidityBalance,
                vars.compoundedBorrowBalance,
                vars.originationFee,
                vars.userUsesReserveAsCollateral
            ) = core.getUserBasicReserveData(vars.currentReserve, _user);

            if (vars.compoundedLiquidityBalance == 0 && vars.compoundedBorrowBalance == 0) {
                continue;
            }

            //fetch reserve data
            (vars.reserveDecimals, vars.baseLtv, vars.liquidationThreshold, vars.usageAsCollateralEnabled) = core
                .getReserveConfiguration(vars.currentReserve);

            vars.tokenUnit = 10**vars.reserveDecimals;
            vars.reserveUnitPrice = oracle.getAssetPrice(vars.currentReserve);

            //liquidity and collateral balance
            if (vars.compoundedLiquidityBalance > 0) {
                uint256 liquidityBalanceETH = vars.reserveUnitPrice.mul(vars.compoundedLiquidityBalance).div(
                    vars.tokenUnit
                );
                totalLiquidityBalanceETH = totalLiquidityBalanceETH.add(liquidityBalanceETH);

                if (vars.usageAsCollateralEnabled && vars.userUsesReserveAsCollateral) {
                    totalCollateralBalanceETH = totalCollateralBalanceETH.add(liquidityBalanceETH);
                    currentLtv = currentLtv.add(liquidityBalanceETH.mul(vars.baseLtv));
                    currentLiquidationThreshold = currentLiquidationThreshold.add(
                        liquidityBalanceETH.mul(vars.liquidationThreshold)
                    );
                }
            }

            if (vars.compoundedBorrowBalance > 0) {
                totalBorrowBalanceETH = totalBorrowBalanceETH.add(
                    vars.reserveUnitPrice.mul(vars.compoundedBorrowBalance).div(vars.tokenUnit)
                );
                totalFeesETH = totalFeesETH.add(vars.originationFee.mul(vars.reserveUnitPrice).div(vars.tokenUnit));
            }
        }

        currentLtv = totalCollateralBalanceETH > 0 ? currentLtv.div(totalCollateralBalanceETH) : 0;
        currentLiquidationThreshold = totalCollateralBalanceETH > 0
            ? currentLiquidationThreshold.div(totalCollateralBalanceETH)
            : 0;

        healthFactor = calculateHealthFactorFromBalancesInternal(
            totalCollateralBalanceETH,
            totalBorrowBalanceETH,
            totalFeesETH,
            currentLiquidationThreshold
        );
        healthFactorBelowThreshold = healthFactor < HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    struct balanceDecreaseAllowedLocalVars {
        uint256 decimals;
        uint256 collateralBalanceETH;
        uint256 borrowBalanceETH;
        uint256 totalFeesETH;
        uint256 currentLiquidationThreshold;
        uint256 reserveLiquidationThreshold;
        uint256 amountToDecreaseETH;
        uint256 collateralBalancefterDecrease;
        uint256 liquidationThresholdAfterDecrease;
        uint256 healthFactorAfterDecrease;
        bool reserveUsageAsCollateralEnabled;
    }

    function balanceDecreaseAllowed(
        address _reserve,
        address _user,
        uint256 _amount
    ) external view returns (bool) {
        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        balanceDecreaseAllowedLocalVars memory vars;

        (vars.decimals, , vars.reserveLiquidationThreshold, vars.reserveUsageAsCollateralEnabled) = core
            .getReserveConfiguration(_reserve);

        if (!vars.reserveUsageAsCollateralEnabled || !core.isUserUseReserveAsCollateralEnabled(_reserve, _user)) {
            return true; //if reserve is not used as collateral, no reasons to block the transfer
        }

        (
            ,
            vars.collateralBalanceETH,
            vars.borrowBalanceETH,
            vars.totalFeesETH,
            ,
            vars.currentLiquidationThreshold,
            ,

        ) = calculateUserGlobalData(_user);

        if (vars.borrowBalanceETH == 0) {
            return true; //no borrows - no reasons to block the transfer
        }

        IPriceOracle oracle = IPriceOracle(addressesProvider.getPriceOracle());

        vars.amountToDecreaseETH = oracle.getAssetPrice(_reserve).mul(_amount).div(10**vars.decimals);

        vars.collateralBalancefterDecrease = vars.collateralBalanceETH.sub(vars.amountToDecreaseETH);

        //if there is a borrow, there can't be 0 collateral
        if (vars.collateralBalancefterDecrease == 0) {
            return false;
        }

        vars.liquidationThresholdAfterDecrease = vars
            .collateralBalanceETH
            .mul(vars.currentLiquidationThreshold)
            .sub(vars.amountToDecreaseETH.mul(vars.reserveLiquidationThreshold))
            .div(vars.collateralBalancefterDecrease);

        uint256 healthFactorAfterDecrease = calculateHealthFactorFromBalancesInternal(
            vars.collateralBalancefterDecrease,
            vars.borrowBalanceETH,
            vars.totalFeesETH,
            vars.liquidationThresholdAfterDecrease
        );

        return healthFactorAfterDecrease > HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    function calculateCollateralNeededInETH(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        uint256 _userCurrentBorrowBalanceTH,
        uint256 _userCurrentFeesETH,
        uint256 _userCurrentLtv
    ) external view returns (uint256) {
        uint256 reserveDecimals = core.getReserveDecimals(_reserve);

        IPriceOracle oracle = IPriceOracle(addressesProvider.getPriceOracle());

        uint256 requestedBorrowAmountETH = oracle.getAssetPrice(_reserve).mul(_amount.add(_fee)).div(
            10**reserveDecimals
        ); //price is in ether

        //add the current already borrowed amount to the amount requested to calculate the total collateral needed.
        uint256 collateralNeededInETH = _userCurrentBorrowBalanceTH
            .add(_userCurrentFeesETH)
            .add(requestedBorrowAmountETH)
            .mul(100)
            .div(_userCurrentLtv); //LTV is calculated in percentage

        return collateralNeededInETH;
    }

    function calculateAvailableBorrowsETHInternal(
        uint256 collateralBalanceETH,
        uint256 borrowBalanceETH,
        uint256 totalFeesETH,
        uint256 ltv
    ) internal view returns (uint256) {
        uint256 availableBorrowsETH = collateralBalanceETH.mul(ltv).div(100); //ltv is in percentage

        if (availableBorrowsETH < borrowBalanceETH) {
            return 0;
        }

        availableBorrowsETH = availableBorrowsETH.sub(borrowBalanceETH.add(totalFeesETH));
        //calculate fee
        uint256 borrowFee = 10;
        return availableBorrowsETH.sub(borrowFee);
    }

    function calculateHealthFactorFromBalancesInternal(
        uint256 collateralBalanceETH,
        uint256 borrowBalanceETH,
        uint256 totalFeesETH,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        if (borrowBalanceETH == 0) return uint256(-1);

        return (collateralBalanceETH.mul(liquidationThreshold).div(100)).wadDiv(borrowBalanceETH.add(totalFeesETH));
    }

    function getHealthFactorLiquidationThreshold() public pure returns (uint256) {
        return HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    function getReserveConfigurationData(address _reserve)
        external
        view
        returns (
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            address rateStrategyAddress,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive
        )
    {
        (, ltv, liquidationThreshold, usageAsCollateralEnabled) = core.getReserveConfiguration(_reserve);
        stableBorrowRateEnabled = core.getReserveIsStableBorrowRateEnabled(_reserve);
        borrowingEnabled = core.isReserveBorrowingEnabled(_reserve);
        isActive = core.getReserveIsActive(_reserve);
        liquidationBonus = core.getReserveLiquidationBonus(_reserve);

        rateStrategyAddress = core.getReserveInterestRateStrategyAddress(_reserve);
    }

    function getReserveData(address _reserve)
        external
        view
        returns (
            uint256 totalLiquidity,
            uint256 availableLiquidity,
            uint256 totalBorrowsStable,
            uint256 totalBorrowsVariable,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 utilizationRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            address cTokenAddress,
            uint40 lastUpdateTimestamp
        )
    {
        totalLiquidity = core.getReserveTotalLiquidity(_reserve);
        availableLiquidity = core.getReserveAvailableLiquidity(_reserve);
        totalBorrowsStable = core.getReserveTotalBorrowsStable(_reserve);
        totalBorrowsVariable = core.getReserveTotalBorrowsVariable(_reserve);
        liquidityRate = core.getReserveCurrentLiquidityRate(_reserve);
        variableBorrowRate = core.getReserveCurrentVariableBorrowRate(_reserve);
        utilizationRate = core.getReserveUtilizationRate(_reserve);
        liquidityIndex = core.getReserveLiquidityCumulativeIndex(_reserve);
        variableBorrowIndex = core.getReserveVariableBorrowsCumulativeIndex(_reserve);
        cTokenAddress = core.getReserveCTokenAddress(_reserve);
        lastUpdateTimestamp = core.getReserveLastUpdate(_reserve);
    }

    function getUserAccountData(address _user)
        external
        view
        returns (
            uint256 totalLiquidityETH,
            uint256 totalCollateralETH,
            uint256 totalBorrowsETH,
            uint256 totalFeesETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        (
            totalLiquidityETH,
            totalCollateralETH,
            totalBorrowsETH,
            totalFeesETH,
            ltv,
            currentLiquidationThreshold,
            healthFactor,

        ) = calculateUserGlobalData(_user);

        availableBorrowsETH = calculateAvailableBorrowsETHInternal(
            totalCollateralETH,
            totalBorrowsETH,
            totalFeesETH,
            ltv
        );
    }

    function getUserReserveData(address _reserve, address _user)
        external
        view
        returns (
            uint256 currentCTokenBalance,
            uint256 currentBorrowBalance,
            uint256 principalBorrowBalance,
            uint256 borrowRate,
            uint256 liquidityRate,
            uint256 originationFee,
            uint256 variableBorrowIndex,
            uint256 lastUpdateTimestamp,
            bool usageAsCollateralEnabled
        )
    {
        currentCTokenBalance = CToken(core.getReserveCTokenAddress(_reserve)).balanceOf(_user);
        (principalBorrowBalance, currentBorrowBalance, ) = core.getUserBorrowBalances(_reserve, _user);

        borrowRate = core.getReserveCurrentVariableBorrowRate(_reserve);

        liquidityRate = core.getReserveCurrentLiquidityRate(_reserve);
        originationFee = core.getUserOriginationFee(_reserve, _user);
        variableBorrowIndex = core.getUserVariableBorrowCumulativeIndex(_reserve, _user);
        lastUpdateTimestamp = core.getUserLastUpdate(_reserve, _user);
        usageAsCollateralEnabled = core.isUserUseReserveAsCollateralEnabled(_reserve, _user);
    }
}
