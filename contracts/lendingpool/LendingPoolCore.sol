// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import '../libraries/CoreLibrary.sol';
import '../configuration/LendingPoolAddressesProvider.sol';
import '../interfaces/IReserveInterestRateStrategy.sol';
import '../libraries/WadRayMath.sol';
import '../tokenization/CToken.sol';
import '../libraries/EthAddressLib.sol';

contract LendingPoolCore is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using CoreLibrary for CoreLibrary.ReserveData;
    using CoreLibrary for CoreLibrary.UserReserveData;
    using SafeERC20 for ERC20;
    using Address for address payable;

    event ReserveUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 stableBorrowRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    address public lendingPoolAddress;

    LendingPoolAddressesProvider public addressesProvider;

    modifier onlyLendingPool {
        require(lendingPoolAddress == msg.sender, 'The caller must be a lending pool contract');
        _;
    }

    modifier onlyLendingPoolConfigurator {
        require(true, 'The caller must be a lending pool configurator contract');
        _;
    }

    mapping(address => CoreLibrary.ReserveData) internal reserves;
    mapping(address => mapping(address => CoreLibrary.UserReserveData)) internal usersReserveData;

    address[] public reservesList;

    function initialize(LendingPoolAddressesProvider _addressesProvider) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        addressesProvider = _addressesProvider;
        refreshConfigInternal();
    }

    function updateStateOnDeposit(
        address _reserve,
        address _user,
        uint256 _amount,
        bool _isFirstDeposit
    ) external onlyLendingPool {
        reserves[_reserve].updateCumulativeIndexes();
        updateReserveInterestRatesAndTimestampInternal(_reserve, _amount, 0);

        if (_isFirstDeposit) {
            //if this is the first deposit of the user, we configure the deposit as enabled to be used as collateral
            setUserUseReserveAsCollateral(_reserve, _user, true);
        }
    }

    function updateStateOnRedeem(
        address _reserve,
        address _user,
        uint256 _amountRedeemed,
        bool _userRedeemedEverything
    ) external onlyLendingPool {
        //compound liquidity and variable borrow interests
        reserves[_reserve].updateCumulativeIndexes();
        updateReserveInterestRatesAndTimestampInternal(_reserve, 0, _amountRedeemed);

        //if user redeemed everything the useReserveAsCollateral flag is reset
        if (_userRedeemedEverything) {
            setUserUseReserveAsCollateral(_reserve, _user, false);
        }
    }

    function updateStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _amountBorrowed,
        uint256 _borrowFee,
        CoreLibrary.InterestRateMode _rateMode
    ) external onlyLendingPool returns (uint256, uint256) {
        // getting the previous borrow data of the user
        (uint256 principalBorrowBalance, , uint256 balanceIncrease) = getUserBorrowBalances(_reserve, _user);

        updateReserveStateOnBorrowInternal(
            _reserve,
            _user,
            principalBorrowBalance,
            balanceIncrease,
            _amountBorrowed,
            _rateMode
        );

        updateUserStateOnBorrowInternal(_reserve, _user, _amountBorrowed, balanceIncrease, _borrowFee, _rateMode);

        updateReserveInterestRatesAndTimestampInternal(_reserve, 0, _amountBorrowed);

        return (getUserCurrentBorrowRate(_reserve, _user), balanceIncrease);
    }

    function updateStateOnRepay(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _originationFeeRepaid,
        uint256 _balanceIncrease,
        bool _repaidWholeLoan
    ) external onlyLendingPool {
        updateReserveStateOnRepayInternal(_reserve, _user, _paybackAmountMinusFees, _balanceIncrease);
        updateUserStateOnRepayInternal(
            _reserve,
            _user,
            _paybackAmountMinusFees,
            _originationFeeRepaid,
            _balanceIncrease,
            _repaidWholeLoan
        );

        updateReserveInterestRatesAndTimestampInternal(_reserve, _paybackAmountMinusFees, 0);
    }

    function updateStateOnLiquidation(
        address _principalReserve,
        address _collateralReserve,
        address _user,
        uint256 _amountToLiquidate,
        uint256 _collateralToLiquidate,
        uint256 _feeLiquidated,
        uint256 _liquidatedCollateralForFee,
        uint256 _balanceIncrease,
        bool _liquidatorReceivesCToken
    ) external onlyLendingPool {
        updatePrincipalReserveStateOnLiquidationInternal(
            _principalReserve,
            _user,
            _amountToLiquidate,
            _balanceIncrease
        );

        updateCollateralReserveStateOnLiquidationInternal(_collateralReserve);

        updateUserStateOnLiquidationInternal(
            _principalReserve,
            _user,
            _amountToLiquidate,
            _feeLiquidated,
            _balanceIncrease
        );

        updateReserveInterestRatesAndTimestampInternal(_principalReserve, _amountToLiquidate, 0);

        if (!_liquidatorReceivesCToken) {
            updateReserveInterestRatesAndTimestampInternal(
                _collateralReserve,
                0,
                _collateralToLiquidate.add(_liquidatedCollateralForFee)
            );
        }
    }

    function setUserUseReserveAsCollateral(
        address _reserve,
        address _user,
        bool _useAsCollateral
    ) public onlyLendingPool {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        user.useAsCollateral = _useAsCollateral;
    }

    function callback() external payable {
        //only contracts can send ETH to the core
        require(msg.sender.isContract(), 'Only contracts can send ether to the Lending pool core');
    }

    function transferToUser(
        address _reserve,
        address payable _user,
        uint256 _amount
    ) external onlyLendingPool {
        if (_reserve != EthAddressLib.ethAddress()) {
            ERC20(_reserve).safeTransfer(_user, _amount);
        } else {
            //solium-disable-next-line
            (bool result, ) = _user.call.value(_amount).gas(50000)('');
            require(result, 'Transfer of ETH failed');
        }
    }

    function transferToFeeCollectionAddress(
        address _token,
        address _user,
        uint256 _amount,
        address _destination
    ) external payable onlyLendingPool {
        address payable feeAddress = address(uint160(_destination)); //cast the address to payable

        if (_token != EthAddressLib.ethAddress()) {
            require(
                msg.value == 0,
                'User is sending ETH along with the ERC20 transfer. Check the value attribute of the transaction'
            );
            ERC20(_token).safeTransferFrom(_user, feeAddress, _amount);
        } else {
            require(msg.value >= _amount, 'The amount and the value sent to deposit do not match');
            //solium-disable-next-line
            (bool result, ) = feeAddress.call.value(_amount).gas(50000)('');
            require(result, 'Transfer of ETH failed');
        }
    }

    function liquidateFee(
        address _token,
        uint256 _amount,
        address _destination
    ) external payable onlyLendingPool {
        address payable feeAddress = address(uint160(_destination)); //cast the address to payable
        require(msg.value == 0, 'Fee liquidation does not require any transfer of value');

        if (_token != EthAddressLib.ethAddress()) {
            ERC20(_token).safeTransfer(feeAddress, _amount);
        } else {
            //solium-disable-next-line
            (bool result, ) = feeAddress.call.value(_amount).gas(50000)('');
            require(result, 'Transfer of ETH failed');
        }
    }

    function transferToReserve(
        address _reserve,
        address payable _user,
        uint256 _amount
    ) external payable onlyLendingPool {
        if (_reserve != EthAddressLib.ethAddress()) {
            require(msg.value == 0, 'User is sending ETH along with the ERC20 transfer.');
            ERC20(_reserve).safeTransferFrom(_user, address(this), _amount);
        } else {
            require(msg.value >= _amount, 'The amount and the value sent to deposit do not match');

            if (msg.value > _amount) {
                //send back excess ETH
                uint256 excessAmount = msg.value.sub(_amount);
                //solium-disable-next-line
                (bool result, ) = _user.call.value(excessAmount).gas(50000)('');
                require(result, 'Transfer of ETH failed');
            }
        }
    }

    function getUserBasicReserveData(address _reserve, address _user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        uint256 underlyingBalance = getUserUnderlyingAssetBalance(_reserve, _user);

        if (user.principalBorrowBalance == 0) {
            return (underlyingBalance, 0, 0, user.useAsCollateral);
        }

        return (underlyingBalance, user.getCompoundedBorrowBalance(reserve), user.originationFee, user.useAsCollateral);
    }

    function getUserUnderlyingAssetBalance(address _reserve, address _user) public view returns (uint256) {
        CToken cToken = CToken(reserves[_reserve].cTokenAddress);
        return cToken.balanceOf(_user);
    }

    function getReserveCTokenAddress(address _reserve) public view returns (address) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.cTokenAddress;
    }

    function getReserveAvailableLiquidity(address _reserve) public view returns (uint256) {
        uint256 balance = 0;

        if (_reserve == EthAddressLib.ethAddress()) {
            balance = address(this).balance;
        } else {
            balance = IERC20(_reserve).balanceOf(address(this));
        }
        return balance;
    }

    function getReserveTotalLiquidity(address _reserve) public view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return getReserveAvailableLiquidity(_reserve).add(reserve.getTotalBorrows());
    }

    function getReserveNormalizedIncome(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.getNormalizedIncome();
    }

    function getReserveTotalBorrows(address _reserve) public view returns (uint256) {
        return reserves[_reserve].getTotalBorrows();
    }

    function getReserveTotalBorrowsStable(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.totalBorrowsStable;
    }

    function getReserveTotalBorrowsVariable(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.totalBorrowsVariable;
    }

    function getReserveLiquidationThreshold(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.liquidationThreshold;
    }

    function getReserveLiquidationBonus(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.liquidationBonus;
    }

    function getReserveCurrentVariableBorrowRate(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        if (reserve.currentVariableBorrowRate == 0) {
            return IReserveInterestRateStrategy(reserve.interestRateStrategyAddress).getBaseVariableBorrowRate();
        }
        return reserve.currentVariableBorrowRate;
    }

    function getReserveCurrentLiquidityRate(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.currentLiquidityRate;
    }

    function getReserveLiquidityCumulativeIndex(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.lastLiquidityCumulativeIndex;
    }

    function getReserveVariableBorrowsCumulativeIndex(address _reserve) external view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.lastVariableBorrowCumulativeIndex;
    }

    function getReserveConfiguration(address _reserve)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        uint256 decimals;
        uint256 baseLTVasCollateral;
        uint256 liquidationThreshold;
        bool usageAsCollateralEnabled;

        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        decimals = reserve.decimals;
        baseLTVasCollateral = reserve.baseLTVasCollateral;
        liquidationThreshold = reserve.liquidationThreshold;
        usageAsCollateralEnabled = reserve.usageAsCollateralEnabled;

        return (decimals, baseLTVasCollateral, liquidationThreshold, usageAsCollateralEnabled);
    }

    function getReserveDecimals(address _reserve) external view returns (uint256) {
        return reserves[_reserve].decimals;
    }

    function isReserveBorrowingEnabled(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.borrowingEnabled;
    }

    function isReserveUsageAsCollateralEnabled(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.usageAsCollateralEnabled;
    }

    function getReserveIsStableBorrowRateEnabled(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.isStableBorrowRateEnabled;
    }

    function getReserveIsActive(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.isActive;
    }

    function getReserveIsFreezed(address _reserve) external view returns (bool) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.isFreezed;
    }

    function getReserveLastUpdate(address _reserve) external view returns (uint40 timestamp) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        timestamp = reserve.lastUpdateTimestamp;
    }

    function getReserveUtilizationRate(address _reserve) public view returns (uint256) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        uint256 totalBorrows = reserve.getTotalBorrows();

        if (totalBorrows == 0) {
            return 0;
        }

        uint256 availableLiquidity = getReserveAvailableLiquidity(_reserve);

        return totalBorrows.rayDiv(availableLiquidity.add(totalBorrows));
    }

    function getReserves() external view returns (address[] memory) {
        return reservesList;
    }

    function isUserUseReserveAsCollateralEnabled(address _reserve, address _user) external view returns (bool) {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        return user.useAsCollateral;
    }

    function getUserOriginationFee(address _reserve, address _user) external view returns (uint256) {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        return user.originationFee;
    }

    function getUserCurrentBorrowRateMode(address _reserve, address _user)
        public
        view
        returns (CoreLibrary.InterestRateMode)
    {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        if (user.principalBorrowBalance == 0) {
            return CoreLibrary.InterestRateMode.NONE;
        }

        return user.stableBorrowRate > 0 ? CoreLibrary.InterestRateMode.STABLE : CoreLibrary.InterestRateMode.VARIABLE;
    }

    function getUserCurrentBorrowRate(address _reserve, address _user) internal view returns (uint256) {
        CoreLibrary.InterestRateMode rateMode = getUserCurrentBorrowRateMode(_reserve, _user);

        if (rateMode == CoreLibrary.InterestRateMode.NONE) {
            return 0;
        }

        return
            rateMode == CoreLibrary.InterestRateMode.STABLE
                ? usersReserveData[_user][_reserve].stableBorrowRate
                : reserves[_reserve].currentVariableBorrowRate;
    }

    function getUserBorrowBalances(address _reserve, address _user)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        if (user.principalBorrowBalance == 0) {
            return (0, 0, 0);
        }

        uint256 principal = user.principalBorrowBalance;
        uint256 compoundedBalance = CoreLibrary.getCompoundedBorrowBalance(user, reserves[_reserve]);
        return (principal, compoundedBalance, compoundedBalance.sub(principal));
    }

    function getUserVariableBorrowCumulativeIndex(address _reserve, address _user) external view returns (uint256) {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        return user.lastVariableBorrowCumulativeIndex;
    }

    function getUserLastUpdate(address _reserve, address _user) external view returns (uint256 timestamp) {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        timestamp = user.lastUpdateTimestamp;
    }

    function refreshConfiguration() external onlyLendingPoolConfigurator {
        refreshConfigInternal();
    }

    function initReserve(
        address _reserve,
        address _cTokenAddress,
        uint256 _decimals,
        address _interestRateStrategyAddress
    ) external onlyLendingPoolConfigurator {
        reserves[_reserve].init(_cTokenAddress, _decimals, _interestRateStrategyAddress);
        addReserveToListInternal(_reserve);
    }

    function enableBorrowingOnReserve(address _reserve, bool _stableBorrowRateEnabled)
        external
        onlyLendingPoolConfigurator
    {
        reserves[_reserve].enableBorrowing(_stableBorrowRateEnabled);
    }

    function disableBorrowingOnReserve(address _reserve) external onlyLendingPoolConfigurator {
        reserves[_reserve].disableBorrowing();
    }

    function enableReserveAsCollateral(
        address _reserve,
        uint256 _baseLTVasCollateral,
        uint256 _liquidationThreshold,
        uint256 _liquidationBonus
    ) external onlyLendingPoolConfigurator {
        reserves[_reserve].enableAsCollateral(_baseLTVasCollateral, _liquidationThreshold, _liquidationBonus);
    }

    function disableReserveAsCollateral(address _reserve) external onlyLendingPoolConfigurator {
        reserves[_reserve].disableAsCollateral();
    }

    function enableReserveStableBorrowRate(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.isStableBorrowRateEnabled = true;
    }

    function disableReserveStableBorrowRate(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.isStableBorrowRateEnabled = false;
    }

    function activateReserve(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        require(
            reserve.lastLiquidityCumulativeIndex > 0 && reserve.lastVariableBorrowCumulativeIndex > 0,
            'Reserve has not been initialized yet'
        );
        reserve.isActive = true;
    }

    function deactivateReserve(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.isActive = false;
    }

    function freezeReserve(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.isFreezed = true;
    }

    function unfreezeReserve(address _reserve) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.isFreezed = false;
    }

    function setReserveBaseLTVasCollateral(address _reserve, uint256 _ltv) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.baseLTVasCollateral = _ltv;
    }

    function setReserveLiquidationThreshold(address _reserve, uint256 _threshold) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.liquidationThreshold = _threshold;
    }

    function setReserveLiquidationBonus(address _reserve, uint256 _bonus) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.liquidationBonus = _bonus;
    }

    function setReserveDecimals(address _reserve, uint256 _decimals) external onlyLendingPoolConfigurator {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        reserve.decimals = _decimals;
    }

    function updateReserveStateOnBorrowInternal(
        address _reserve,
        address _user,
        uint256 _principalBorrowBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        CoreLibrary.InterestRateMode _rateMode
    ) internal {
        reserves[_reserve].updateCumulativeIndexes();

        //increasing reserve total borrows to account for the new borrow balance of the user
        //NOTE: Depending on the previous borrow mode, the borrows might need to be switched from variable to stable or vice versa

        updateReserveTotalBorrowsByRateModeInternal(
            _reserve,
            _user,
            _principalBorrowBalance,
            _balanceIncrease,
            _amountBorrowed,
            _rateMode
        );
    }

    function updateUserStateOnBorrowInternal(
        address _reserve,
        address _user,
        uint256 _amountBorrowed,
        uint256 _balanceIncrease,
        uint256 _fee,
        CoreLibrary.InterestRateMode _rateMode
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        if (_rateMode == CoreLibrary.InterestRateMode.STABLE) {
            //stable
            //reset the user variable index, and update the stable rate
            user.stableBorrowRate = reserve.currentStableBorrowRate;
            user.lastVariableBorrowCumulativeIndex = 0;
        } else if (_rateMode == CoreLibrary.InterestRateMode.VARIABLE) {
            //variable
            //reset the user stable rate, and store the new borrow index
            user.stableBorrowRate = 0;
            user.lastVariableBorrowCumulativeIndex = reserve.lastVariableBorrowCumulativeIndex;
        } else {
            revert('Invalid borrow rate mode');
        }
        //increase the principal borrows and the origination fee
        user.principalBorrowBalance = user.principalBorrowBalance.add(_amountBorrowed).add(_balanceIncrease);
        user.originationFee = user.originationFee.add(_fee);

        //solium-disable-next-line
        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    function updateReserveStateOnRepayInternal(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _balanceIncrease
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        CoreLibrary.InterestRateMode borrowRateMode = getUserCurrentBorrowRateMode(_reserve, _user);

        //update the indexes
        reserves[_reserve].updateCumulativeIndexes();

        //compound the cumulated interest to the borrow balance and then subtracting the payback amount
        if (borrowRateMode == CoreLibrary.InterestRateMode.STABLE) {
            reserve.increaseTotalBorrowsStableAndUpdateAverageRate(_balanceIncrease, user.stableBorrowRate);
            reserve.decreaseTotalBorrowsStableAndUpdateAverageRate(_paybackAmountMinusFees, user.stableBorrowRate);
        } else {
            reserve.increaseTotalBorrowsVariable(_balanceIncrease);
            reserve.decreaseTotalBorrowsVariable(_paybackAmountMinusFees);
        }
    }

    function updateUserStateOnRepayInternal(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _originationFeeRepaid,
        uint256 _balanceIncrease,
        bool _repaidWholeLoan
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        //update the user principal borrow balance, adding the cumulated interest and then subtracting the payback amount
        user.principalBorrowBalance = user.principalBorrowBalance.add(_balanceIncrease).sub(_paybackAmountMinusFees);
        user.lastVariableBorrowCumulativeIndex = reserve.lastVariableBorrowCumulativeIndex;

        //if the balance decrease is equal to the previous principal (user is repaying the whole loan)
        //and the rate mode is stable, we reset the interest rate mode of the user
        if (_repaidWholeLoan) {
            user.stableBorrowRate = 0;
            user.lastVariableBorrowCumulativeIndex = 0;
        }
        user.originationFee = user.originationFee.sub(_originationFeeRepaid);

        //solium-disable-next-line
        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    function updatePrincipalReserveStateOnLiquidationInternal(
        address _principalReserve,
        address _user,
        uint256 _amountToLiquidate,
        uint256 _balanceIncrease
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_principalReserve];
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_principalReserve];

        //update principal reserve data
        reserve.updateCumulativeIndexes();

        CoreLibrary.InterestRateMode borrowRateMode = getUserCurrentBorrowRateMode(_principalReserve, _user);

        if (borrowRateMode == CoreLibrary.InterestRateMode.STABLE) {
            //increase the total borrows by the compounded interest
            reserve.increaseTotalBorrowsStableAndUpdateAverageRate(_balanceIncrease, user.stableBorrowRate);

            //decrease by the actual amount to liquidate
            reserve.decreaseTotalBorrowsStableAndUpdateAverageRate(_amountToLiquidate, user.stableBorrowRate);
        } else {
            //increase the total borrows by the compounded interest
            reserve.increaseTotalBorrowsVariable(_balanceIncrease);

            //decrease by the actual amount to liquidate
            reserve.decreaseTotalBorrowsVariable(_amountToLiquidate);
        }
    }

    function updateCollateralReserveStateOnLiquidationInternal(address _collateralReserve) internal {
        //update collateral reserve
        reserves[_collateralReserve].updateCumulativeIndexes();
    }

    function updateUserStateOnLiquidationInternal(
        address _reserve,
        address _user,
        uint256 _amountToLiquidate,
        uint256 _feeLiquidated,
        uint256 _balanceIncrease
    ) internal {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        //first increase by the compounded interest, then decrease by the liquidated amount
        user.principalBorrowBalance = user.principalBorrowBalance.add(_balanceIncrease).sub(_amountToLiquidate);

        if (getUserCurrentBorrowRateMode(_reserve, _user) == CoreLibrary.InterestRateMode.VARIABLE) {
            user.lastVariableBorrowCumulativeIndex = reserve.lastVariableBorrowCumulativeIndex;
        }

        if (_feeLiquidated > 0) {
            user.originationFee = user.originationFee.sub(_feeLiquidated);
        }

        //solium-disable-next-line
        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    function updateReserveStateOnRebalanceInternal(
        address _reserve,
        address _user,
        uint256 _balanceIncrease
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];

        reserve.updateCumulativeIndexes();

        reserve.increaseTotalBorrowsStableAndUpdateAverageRate(_balanceIncrease, user.stableBorrowRate);
    }

    function updateUserStateOnRebalanceInternal(
        address _reserve,
        address _user,
        uint256 _balanceIncrease
    ) internal {
        CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        user.principalBorrowBalance = user.principalBorrowBalance.add(_balanceIncrease);
        user.stableBorrowRate = reserve.currentStableBorrowRate;

        //solium-disable-next-line
        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    function updateReserveTotalBorrowsByRateModeInternal(
        address _reserve,
        address _user,
        uint256 _principalBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        CoreLibrary.InterestRateMode _newBorrowRateMode
    ) internal {
        CoreLibrary.InterestRateMode previousRateMode = getUserCurrentBorrowRateMode(_reserve, _user);
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];

        if (previousRateMode == CoreLibrary.InterestRateMode.STABLE) {
            CoreLibrary.UserReserveData storage user = usersReserveData[_user][_reserve];
            reserve.decreaseTotalBorrowsStableAndUpdateAverageRate(_principalBalance, user.stableBorrowRate);
        } else if (previousRateMode == CoreLibrary.InterestRateMode.VARIABLE) {
            reserve.decreaseTotalBorrowsVariable(_principalBalance);
        }

        uint256 newPrincipalAmount = _principalBalance.add(_balanceIncrease).add(_amountBorrowed);
        if (_newBorrowRateMode == CoreLibrary.InterestRateMode.STABLE) {
            reserve.increaseTotalBorrowsStableAndUpdateAverageRate(newPrincipalAmount, reserve.currentStableBorrowRate);
        } else if (_newBorrowRateMode == CoreLibrary.InterestRateMode.VARIABLE) {
            reserve.increaseTotalBorrowsVariable(newPrincipalAmount);
        } else {
            revert('Invalid new borrow rate mode');
        }
    }

    function updateReserveInterestRatesAndTimestampInternal(
        address _reserve,
        uint256 _liquidityAdded,
        uint256 _liquidityTaken
    ) internal {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        (uint256 newLiquidityRate, uint256 newVariableRate) = IReserveInterestRateStrategy(
            reserve
                .interestRateStrategyAddress
        )
            .calculateInterestRates(
            _reserve,
            getReserveAvailableLiquidity(_reserve).add(_liquidityAdded).sub(_liquidityTaken),
            reserve.totalBorrowsVariable,
            reserve.currentAverageStableBorrowRate
        );

        uint256 newStableRate = 0;

        reserve.currentLiquidityRate = newLiquidityRate;
        reserve.currentVariableBorrowRate = newVariableRate;

        //solium-disable-next-line
        reserve.lastUpdateTimestamp = uint40(block.timestamp);

        emit ReserveUpdated(
            _reserve,
            newLiquidityRate,
            newStableRate,
            newVariableRate,
            reserve.lastLiquidityCumulativeIndex,
            reserve.lastVariableBorrowCumulativeIndex
        );
    }

    function refreshConfigInternal() internal {
        lendingPoolAddress = addressesProvider.getLendingPool();
    }

    function addReserveToListInternal(address _reserve) internal {
        bool reserveAlreadyAdded = false;
        for (uint256 i = 0; i < reservesList.length; i++) if (reservesList[i] == _reserve) {reserveAlreadyAdded = true;}
        if (!reserveAlreadyAdded) reservesList.push(_reserve);
    }

    function getReserveInterestRateStrategyAddress(address _reserve) public view returns (address) {
        CoreLibrary.ReserveData storage reserve = reserves[_reserve];
        return reserve.interestRateStrategyAddress;
    }
}
