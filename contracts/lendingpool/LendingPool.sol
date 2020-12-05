// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../configuration/LendingPoolAddressesProvider.sol';
import '../configuration/LendingPoolParametersProvider.sol';
import '../tokenization/CToken.sol';
import '../libraries/CoreLibrary.sol';
import '../libraries/WadRayMath.sol';
import '../interfaces/IFeeProvider.sol';
import './LendingPoolCore.sol';
import './LendingPoolDataProvider.sol';
import './LendingPoolLiquidationManager.sol';
import '../libraries/EthAddressLib.sol';

/**
 * @title LendingPool contract
 * @notice Implements the actions of the LendingPool, and exposes accessory methods to fetch the users and reserve data
 * @author Aave
 **/

contract LendingPool is ReentrancyGuard, VersionedInitializable {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using Address for address;

    LendingPoolAddressesProvider public addressesProvider;
    LendingPoolCore public core;
    LendingPoolDataProvider public dataProvider;
    LendingPoolParametersProvider public parametersProvider;
    IFeeProvider feeProvider;

    /**
     * @dev emitted on deposit
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @param _amount the amount to be deposited
     * @param _referral the referral number of the action
     * @param _timestamp the timestamp of the action
     **/
    event Deposit(
        address indexed _reserve,
        address indexed _user,
        uint256 _amount,
        uint16 indexed _referral,
        uint256 _timestamp
    );

    /**
     * @dev emitted during a redeem action.
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @param _amount the amount to be deposited
     * @param _timestamp the timestamp of the action
     **/
    event RedeemUnderlying(address indexed _reserve, address indexed _user, uint256 _amount, uint256 _timestamp);

    /**
     * @dev emitted on borrow
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @param _amount the amount to be deposited
     * @param _borrowRateMode the rate mode, can be either 1-stable or 2-variable
     * @param _borrowRate the rate at which the user has borrowed
     * @param _originationFee the origination fee to be paid by the user
     * @param _borrowBalanceIncrease the balance increase since the last borrow, 0 if it's the first time borrowing
     * @param _referral the referral number of the action
     * @param _timestamp the timestamp of the action
     **/
    event Borrow(
        address indexed _reserve,
        address indexed _user,
        uint256 _amount,
        uint256 _borrowRateMode,
        uint256 _borrowRate,
        uint256 _originationFee,
        uint256 _borrowBalanceIncrease,
        uint16 indexed _referral,
        uint256 _timestamp
    );

    /**
     * @dev emitted on repay
     * @param _reserve the address of the reserve
     * @param _user the address of the user for which the repay has been executed
     * @param _repayer the address of the user that has performed the repay action
     * @param _amountMinusFees the amount repaid minus fees
     * @param _fees the fees repaid
     * @param _borrowBalanceIncrease the balance increase since the last action
     * @param _timestamp the timestamp of the action
     **/
    event Repay(
        address indexed _reserve,
        address indexed _user,
        address indexed _repayer,
        uint256 _amountMinusFees,
        uint256 _fees,
        uint256 _borrowBalanceIncrease,
        uint256 _timestamp
    );


    /**
     * @dev emitted when a user enables a reserve as collateral
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     **/
    event ReserveUsedAsCollateralEnabled(address indexed _reserve, address indexed _user);

    /**
     * @dev emitted when a user disables a reserve as collateral
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     **/
    event ReserveUsedAsCollateralDisabled(address indexed _reserve, address indexed _user);

    /**
     * @dev these events are not emitted directly by the LendingPool
     * but they are declared here as the LendingPoolLiquidationManager
     * is executed using a delegateCall().
     * This allows to have the events in the generated ABI for LendingPool.
     **/

    /**
     * @dev emitted when a borrow fee is liquidated
     * @param _collateral the address of the collateral being liquidated
     * @param _reserve the address of the reserve
     * @param _user the address of the user being liquidated
     * @param _feeLiquidated the total fee liquidated
     * @param _liquidatedCollateralForFee the amount of collateral received by the protocol in exchange for the fee
     * @param _timestamp the timestamp of the action
     **/
    event OriginationFeeLiquidated(
        address indexed _collateral,
        address indexed _reserve,
        address indexed _user,
        uint256 _feeLiquidated,
        uint256 _liquidatedCollateralForFee,
        uint256 _timestamp
    );

    /**
     * @dev emitted when a borrower is liquidated
     * @param _collateral the address of the collateral being liquidated
     * @param _reserve the address of the reserve
     * @param _user the address of the user being liquidated
     * @param _purchaseAmount the total amount liquidated
     * @param _liquidatedCollateralAmount the amount of collateral being liquidated
     * @param _accruedBorrowInterest the amount of interest accrued by the borrower since the last action
     * @param _liquidator the address of the liquidator
     * @param _receiveCToken true if the liquidator wants to receive cTokens, false otherwise
     * @param _timestamp the timestamp of the action
     **/
    event LiquidationCall(
        address indexed _collateral,
        address indexed _reserve,
        address indexed _user,
        uint256 _purchaseAmount,
        uint256 _liquidatedCollateralAmount,
        uint256 _accruedBorrowInterest,
        address _liquidator,
        bool _receiveCToken,
        uint256 _timestamp
    );

    /**
     * @dev functions affected by this modifier can only be invoked by the
     * cToken.sol contract
     * @param _reserve the address of the reserve
     **/
    modifier onlyOverlyingCToken(address _reserve) {
        require(
            msg.sender == core.getReserveCTokenAddress(_reserve),
            'The caller of this function can only be the cToken contract of this reserve'
        );
        _;
    }

    /**
     * @dev functions affected by this modifier can only be invoked if the reserve is active
     * @param _reserve the address of the reserve
     **/
    modifier onlyActiveReserve(address _reserve) {
        requireReserveActiveInternal(_reserve);
        _;
    }

    /**
     * @dev functions affected by this modifier can only be invoked if the reserve is not freezed.
     * A freezed reserve only allows redeems, repays, rebalances and liquidations.
     * @param _reserve the address of the reserve
     **/
    modifier onlyUnfreezedReserve(address _reserve) {
        requireReserveNotFreezedInternal(_reserve);
        _;
    }

    /**
     * @dev functions affected by this modifier can only be invoked if the provided _amount input parameter
     * is not zero.
     * @param _amount the amount provided
     **/
    modifier onlyAmountGreaterThanZero(uint256 _amount) {
        requireAmountGreaterThanZeroInternal(_amount);
        _;
    }

    uint256 public constant UINT_MAX_VALUE = uint256(-1);


    /**
     * @dev this function is invoked by the proxy contract when the LendingPool contract is added to the
     * AddressesProvider.
     * @param _addressesProvider the address of the LendingPoolAddressesProvider registry
     **/
    function initialize(LendingPoolAddressesProvider _addressesProvider) public initializer {
        addressesProvider = _addressesProvider;
        core = LendingPoolCore(addressesProvider.getLendingPoolCore());
        dataProvider = LendingPoolDataProvider(addressesProvider.getLendingPoolDataProvider());
        parametersProvider = LendingPoolParametersProvider(addressesProvider.getLendingPoolParametersProvider());
        feeProvider = IFeeProvider(addressesProvider.getFeeProvider());
    }

    /**
     * @dev deposits The underlying asset into the reserve. A corresponding amount of the overlying asset (cTokens)
     * is minted.
     * @param _reserve the address of the reserve
     * @param _amount the amount to be deposited
     * @param _referralCode integrators are assigned a referral code and can potentially receive rewards.
     **/
    function deposit(
        address _reserve,
        uint256 _amount,
        uint16 _referralCode
    )
        external
        payable
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyUnfreezedReserve(_reserve)
        onlyAmountGreaterThanZero(_amount)
    {
        CToken cToken = CToken(core.getReserveCTokenAddress(_reserve));

        bool isFirstDeposit = cToken.balanceOf(msg.sender) == 0;

        core.updateStateOnDeposit(_reserve, msg.sender, _amount, isFirstDeposit);

        //minting CToken to user 1:1 with the specific exchange rate
        cToken.mintOnDeposit(msg.sender, _amount);

        //transfer to the core contract
        core.transferToReserve.value(msg.value)(_reserve, msg.sender, _amount);

        //solium-disable-next-line
        emit Deposit(_reserve, msg.sender, _amount, _referralCode, block.timestamp);
    }

    /**
     * @dev Redeems the underlying amount of assets requested by _user.
     * This function is executed by the overlying cToken contract in response to a redeem action.
     * @param _reserve the address of the reserve
     * @param _user the address of the user performing the action
     * @param _amount the underlying amount to be redeemed
     **/
    function redeemUnderlying(
        address _reserve,
        address payable _user,
        uint256 _amount,
        uint256 _cTokenBalanceAfterRedeem
    )
        external
        nonReentrant
        onlyOverlyingCToken(_reserve)
        onlyActiveReserve(_reserve)
        onlyAmountGreaterThanZero(_amount)
    {
        uint256 currentAvailableLiquidity = core.getReserveAvailableLiquidity(_reserve);
        require(currentAvailableLiquidity >= _amount, 'There is not enough liquidity available to redeem');

        core.updateStateOnRedeem(_reserve, _user, _amount, _cTokenBalanceAfterRedeem == 0);

        core.transferToUser(_reserve, _user, _amount);

        //solium-disable-next-line
        emit RedeemUnderlying(_reserve, _user, _amount, block.timestamp);
    }

    /**
     * @dev data structures for local computations in the borrow() method.
     */

    struct BorrowLocalVars {
        uint256 principalBorrowBalance;
        uint256 currentLtv;
        uint256 currentLiquidationThreshold;
        uint256 borrowFee;
        uint256 requestedBorrowAmountETH;
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 userTotalFeesETH;
        uint256 borrowBalanceIncrease;
        uint256 currentReserveStableRate;
        uint256 availableLiquidity;
        uint256 reserveDecimals;
        uint256 finalUserBorrowRate;
        bool healthFactorBelowThreshold;
    }

    /**
     * @dev Allows users to borrow a specific amount of the reserve currency, provided that the borrower
     * already deposited enough collateral.
     * @param _reserve the address of the reserve
     * @param _amount the amount to be borrowed
     **/
    function borrow(
        address _reserve,
        uint256 _amount,
        uint16 _referralCode
    )
        external
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyUnfreezedReserve(_reserve)
        onlyAmountGreaterThanZero(_amount)
    {
        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        BorrowLocalVars memory vars;

        //check that the reserve is enabled for borrowing
        require(core.isReserveBorrowingEnabled(_reserve), 'Reserve is not enabled for borrowing');
        //validate interest rate mode
        require(
            uint256(CoreLibrary.InterestRateMode.VARIABLE) == _interestRateMode ||
                uint256(CoreLibrary.InterestRateMode.STABLE) == _interestRateMode,
            'Invalid interest rate mode selected'
        );

        //check that the amount is available in the reserve
        vars.availableLiquidity = core.getReserveAvailableLiquidity(_reserve);

        require(vars.availableLiquidity >= _amount, 'There is not enough liquidity available in the reserve');

        (
            ,
            vars.userCollateralBalanceETH,
            vars.userBorrowBalanceETH,
            vars.userTotalFeesETH,
            vars.currentLtv,
            vars.currentLiquidationThreshold,
            ,
            vars.healthFactorBelowThreshold
        ) = dataProvider.calculateUserGlobalData(msg.sender);

        require(vars.userCollateralBalanceETH > 0, 'The collateral balance is 0');

        require(!vars.healthFactorBelowThreshold, 'The borrower can already be liquidated so he cannot borrow more');

        //calculating fees
        vars.borrowFee = feeProvider.calculateLoanOriginationFee(msg.sender, _amount);

        require(vars.borrowFee > 0, 'The amount to borrow is too small');

        vars.amountOfCollateralNeededETH = dataProvider.calculateCollateralNeededInETH(
            _reserve,
            _amount,
            vars.borrowFee,
            vars.userBorrowBalanceETH,
            vars.userTotalFeesETH,
            vars.currentLtv
        );

        require(
            vars.amountOfCollateralNeededETH <= vars.userCollateralBalanceETH,
            'There is not enough collateral to cover a new borrow'
        );

        //all conditions passed - borrow is accepted
        (vars.finalUserBorrowRate, vars.borrowBalanceIncrease) = core.updateStateOnBorrow(
            _reserve,
            msg.sender,
            _amount,
            vars.borrowFee,
            vars.rateMode
        );

        //if we reached this point, we can transfer
        core.transferToUser(_reserve, msg.sender, _amount);

        emit Borrow(
            _reserve,
            msg.sender,
            _amount,
            vars.finalUserBorrowRate,
            vars.borrowFee,
            vars.borrowBalanceIncrease,
            _referralCode,
            //solium-disable-next-line
            block.timestamp
        );
    }

    /**
     * @notice repays a borrow on the specific reserve, for the specified amount (or for the whole amount, if uint256(-1) is specified).
     * @dev the target user is defined by _onBehalfOf. If there is no repayment on behalf of another account,
     * _onBehalfOf must be equal to msg.sender.
     * @param _reserve the address of the reserve on which the user borrowed
     * @param _amount the amount to repay, or uint256(-1) if the user wants to repay everything
     * @param _onBehalfOf the address for which msg.sender is repaying.
     **/

    struct RepayLocalVars {
        uint256 principalBorrowBalance;
        uint256 compoundedBorrowBalance;
        uint256 borrowBalanceIncrease;
        bool isETH;
        uint256 paybackAmount;
        uint256 paybackAmountMinusFees;
        uint256 currentStableRate;
        uint256 originationFee;
    }

    function repay(
        address _reserve,
        uint256 _amount,
        address payable _onBehalfOf
    ) external payable nonReentrant onlyActiveReserve(_reserve) onlyAmountGreaterThanZero(_amount) {
        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables
        RepayLocalVars memory vars;

        (vars.principalBorrowBalance, vars.compoundedBorrowBalance, vars.borrowBalanceIncrease) = core
            .getUserBorrowBalances(_reserve, _onBehalfOf);

        vars.originationFee = core.getUserOriginationFee(_reserve, _onBehalfOf);
        vars.isETH = EthAddressLib.ethAddress() == _reserve;

        require(vars.compoundedBorrowBalance > 0, 'The user does not have any borrow pending');

        require(
            _amount != UINT_MAX_VALUE || msg.sender == _onBehalfOf,
            'To repay on behalf of an user an explicit amount to repay is needed.'
        );

        //default to max amount
        vars.paybackAmount = vars.compoundedBorrowBalance.add(vars.originationFee);

        if (_amount != UINT_MAX_VALUE && _amount < vars.paybackAmount) {
            vars.paybackAmount = _amount;
        }

        require(!vars.isETH || msg.value >= vars.paybackAmount, 'Invalid msg.value sent for the repayment');

        //if the amount is smaller than the origination fee, just transfer the amount to the fee destination address
        if (vars.paybackAmount <= vars.originationFee) {
            core.updateStateOnRepay(_reserve, _onBehalfOf, 0, vars.paybackAmount, vars.borrowBalanceIncrease, false);

            core.transferToFeeCollectionAddress.value(vars.isETH ? vars.paybackAmount : 0)(
                _reserve,
                _onBehalfOf,
                vars.paybackAmount,
                addressesProvider.getTokenDistributor()
            );

            emit Repay(
                _reserve,
                _onBehalfOf,
                msg.sender,
                0,
                vars.paybackAmount,
                vars.borrowBalanceIncrease,
                //solium-disable-next-line
                block.timestamp
            );
            return;
        }

        vars.paybackAmountMinusFees = vars.paybackAmount.sub(vars.originationFee);

        core.updateStateOnRepay(
            _reserve,
            _onBehalfOf,
            vars.paybackAmountMinusFees,
            vars.originationFee,
            vars.borrowBalanceIncrease,
            vars.compoundedBorrowBalance == vars.paybackAmountMinusFees
        );

        //if the user didn't repay the origination fee, transfer the fee to the fee collection address
        if (vars.originationFee > 0) {
            core.transferToFeeCollectionAddress.value(vars.isETH ? vars.originationFee : 0)(
                _reserve,
                msg.sender,
                vars.originationFee,
                addressesProvider.getTokenDistributor()
            );
        }

        //sending the total msg.value if the transfer is ETH.
        //the transferToReserve() function will take care of sending the
        //excess ETH back to the caller
        core.transferToReserve.value(vars.isETH ? msg.value.sub(vars.originationFee) : 0)(
            _reserve,
            msg.sender,
            vars.paybackAmountMinusFees
        );

        emit Repay(
            _reserve,
            _onBehalfOf,
            msg.sender,
            vars.paybackAmountMinusFees,
            vars.originationFee,
            vars.borrowBalanceIncrease,
            //solium-disable-next-line
            block.timestamp
        );
    }

    /**
     * @dev allows depositors to enable or disable a specific deposit as collateral.
     * @param _reserve the address of the reserve
     * @param _useAsCollateral true if the user wants to user the deposit as collateral, false otherwise.
     **/
    function setUserUseReserveAsCollateral(address _reserve, bool _useAsCollateral)
        external
        nonReentrant
        onlyActiveReserve(_reserve)
        onlyUnfreezedReserve(_reserve)
    {
        uint256 underlyingBalance = core.getUserUnderlyingAssetBalance(_reserve, msg.sender);

        require(underlyingBalance > 0, 'User does not have any liquidity deposited');

        require(
            dataProvider.balanceDecreaseAllowed(_reserve, msg.sender, underlyingBalance),
            'User deposit is already being used as collateral'
        );

        core.setUserUseReserveAsCollateral(_reserve, msg.sender, _useAsCollateral);

        if (_useAsCollateral) {
            emit ReserveUsedAsCollateralEnabled(_reserve, msg.sender);
        } else {
            emit ReserveUsedAsCollateralDisabled(_reserve, msg.sender);
        }
    }

    /**
     * @dev users can invoke this function to liquidate an undercollateralized position.
     * @param _reserve the address of the collateral to liquidated
     * @param _reserve the address of the principal reserve
     * @param _user the address of the borrower
     * @param _purchaseAmount the amount of principal that the liquidator wants to repay
     * @param _receiveCToken true if the liquidators wants to receive the cTokens, false if
     * he wants to receive the underlying asset directly
     **/
    function liquidationCall(
        address _collateral,
        address _reserve,
        address _user,
        uint256 _purchaseAmount,
        bool _receiveCToken
    ) external payable nonReentrant onlyActiveReserve(_reserve) onlyActiveReserve(_collateral) {
        address liquidationManager = addressesProvider.getLendingPoolLiquidationManager();

        //solium-disable-next-line
        (bool success, bytes memory result) = liquidationManager.delegatecall(
            abi.encodeWithSignature(
                'liquidationCall(address,address,address,uint256,bool)',
                _collateral,
                _reserve,
                _user,
                _purchaseAmount,
                _receiveCToken
            )
        );
        require(success, 'Liquidation call failed');

        (uint256 returnCode, string memory returnMessage) = abi.decode(result, (uint256, string));

        if (returnCode != 0) {
            //error found
            revert(string(abi.encodePacked('Liquidation failed: ', returnMessage)));
        }
    }

    /**
     * @dev accessory functions to fetch data from the core contract
     **/

    function getReserveConfigurationData(address _reserve)
        external
        view
        returns (
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            address interestRateStrategyAddress,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive
        )
    {
        return dataProvider.getReserveConfigurationData(_reserve);
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
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 utilizationRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            address cTokenAddress,
            uint40 lastUpdateTimestamp
        )
    {
        return dataProvider.getReserveData(_reserve);
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
        return dataProvider.getUserAccountData(_user);
    }

    function getUserReserveData(address _reserve, address _user)
        external
        view
        returns (
            uint256 currentCTokenBalance,
            uint256 currentBorrowBalance,
            uint256 principalBorrowBalance,
            uint256 borrowRateMode,
            uint256 borrowRate,
            uint256 liquidityRate,
            uint256 originationFee,
            uint256 variableBorrowIndex,
            uint256 lastUpdateTimestamp,
            bool usageAsCollateralEnabled
        )
    {
        return dataProvider.getUserReserveData(_reserve, _user);
    }

    function getReserves() external view returns (address[] memory) {
        return core.getReserves();
    }

    /**
     * @dev internal function to save on code size for the onlyActiveReserve modifier
     **/
    function requireReserveActiveInternal(address _reserve) internal view {
        require(core.getReserveIsActive(_reserve), 'Action requires an active reserve');
    }

    /**
     * @notice internal function to save on code size for the onlyUnfreezedReserve modifier
     **/
    function requireReserveNotFreezedInternal(address _reserve) internal view {
        require(!core.getReserveIsFreezed(_reserve), 'Action requires an unfreezed reserve');
    }

    /**
     * @notice internal function to save on code size for the onlyAmountGreaterThanZero modifier
     **/
    function requireAmountGreaterThanZeroInternal(uint256 _amount) internal pure {
        require(_amount > 0, 'Amount must be greater than 0');
    }
}
