// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

// import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

// import '../configuration/AddressesProvider.sol';
// import '../libraries/ReserveDataLibrary.sol';
// import './Core.sol';
// import './DataProvider.sol';
// import '../libraries/EthAddressLib.sol';

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol';

import '../libraries/WadRayMath.sol';

import '../interfaces/IFacade.sol';
import '../interfaces/IAddressService.sol';
import '../interfaces/IUserReserveDataService.sol';
import '../interfaces/IReserveService.sol';
import '../interfaces/ITreasury.sol';
import '../interfaces/ICToken.sol';
import '../interfaces/IFeeService.sol';
import '../interfaces/IDataQueryService.sol';

/**
 * @title CORE Lending Pool Facade contract
 * @notice Implements the Lending related actions
 * @author CORE
 **/

contract Facade is IFacade, Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using Address for address;

    IAddressService public addressService;
    ITreasury private treasury;
    IReserveService private reserveService;
    IUserReserveDataService private userReserveDataService;
    IFeeService private feeService;
    IDataQueryService private dataQueryService;

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
        uint256 _borrowRate,
        uint256 _originationFee,
        uint256 _borrowBalanceIncrease,
        uint16 indexed _referral,
        uint256 _timestamp
    );

    modifier onlyActiveReserve(address _reserve) {
        require(reserveService.getReserveIsActive(_reserve), 'Action requires an active reserve');
        _;
    }

    modifier onlyPositiveAmount(uint256 _amount) {
        require(_amount > 0, 'Amount must be greater than 0');
        _;
    }
    /**
     * @dev functions affected by this modifier can only be invoked by the
     * aToken.sol contract
     * @param _reserve the address of the reserve
     **/
    modifier onlyReserveOverlyingToken(address _reserve) {
        require(
            msg.sender == reserveService.getReserveOverlyingTokenAddress(_reserve),
            'The caller of this function can only be the aToken contract of this reserve'
        );
        _;
    }

    uint256 public constant UINT_MAX_VALUE = uint256(-1);

    function initialize(IAddressService _addressService) public initializer onlyOwner {
        OwnableUpgradeSafe.__Ownable_init();
        addressService = _addressService;
        refreshConfigInternal();
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
    ) external override payable onlyActiveReserve(_reserve) onlyPositiveAmount(_amount) {
        address cToken = reserveService.getReserveOverlyingTokenAddress(_reserve);

        bool isFirstDeposit = IERC20(cToken).balanceOf(msg.sender) == 0;

        reserveService.updateStateOnDeposit(_reserve, msg.sender, _amount);

        if (isFirstDeposit) {
            userReserveDataService.enableDepositAsCollateral(_reserve, msg.sender);
        }

        //minting CToken to user 1:1 with the specific exchange rate
        ICToken(cToken).mintOnDeposit(msg.sender, _amount);

        //transfer to the core contract
        treasury.transferToTreasury{value: msg.value}(_reserve, msg.sender, _amount);

        //solium-disable-next-line
        emit Deposit(_reserve, msg.sender, _amount, _referralCode, block.timestamp);
    }

    function redeemUnderlying(
        address _reserve,
        address payable _user,
        uint256 _amount,
        uint256 _aTokenBalanceAfterRedeem
    ) external override onlyReserveOverlyingToken(_reserve) onlyActiveReserve(_reserve) onlyPositiveAmount(_amount) {
        uint256 currentAvailableLiquidity = reserveService.getReserveAvailableLiquidity(_reserve);
        require(currentAvailableLiquidity >= _amount, 'There is not enough liquidity available to redeem');

        reserveService.updateStateOnRedeem(_reserve, _user, _amount, _aTokenBalanceAfterRedeem == 0);

        treasury.transferToUser(_reserve, _user, _amount);

        //solium-disable-next-line
        emit RedeemUnderlying(_reserve, _user, _amount, block.timestamp);
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
    ) external onlyActiveReserve(_reserve) onlyPositiveAmount(_amount) {
        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables

        require(reserveService.getReserveIsBorrowingEnabled(_reserve), 'Reserve is not enabled for borrowing');

        uint256 availableLiquidity = reserveService.getReserveAvailableLiquidity(_reserve);

        require(availableLiquidity >= _amount, 'There is not enough liquidity available in the reserve');

        require(
            dataQueryService.getBorrowIsBackedByEnoughCollateral(_reserve, msg.sender, _amount),
            'There is not enough collateral avaialbe'
        );

        //calculating fees
        uint256 borrowFee = feeService.calculateLoanOriginationFee(msg.sender, _amount);

        (uint256 principalBalance, uint256 cumulativeBalance) = dataQueryService.getUserBorrowBalances(
            _reserve,
            msg.sender
        );

        uint256 balanceIncrease = cumulativeBalance.sub(principalBalance).add(_amount);

        //all conditions passed - borrow is accepted
        (uint256 lastVariableBorrowCumulativeIndex, uint256 finalUserBorrowRate) = reserveService.updateStateOnBorrow(
            _reserve,
            balanceIncrease,
            borrowFee
        );

        userReserveDataService.updateStateOnBorrow(
            _reserve,
            msg.sender,
            balanceIncrease,
            lastVariableBorrowCumulativeIndex,
            borrowFee
        );
        //if we reached this point, we can transfer
        treasury.transferToUser(_reserve, msg.sender, _amount);

        emit Borrow(
            _reserve,
            msg.sender,
            _amount,
            finalUserBorrowRate,
            borrowFee,
            balanceIncrease,
            _referralCode,
            //solium-disable-next-line
            block.timestamp
        );
    }

    function refreshConfigInternal() internal {
        treasury = ITreasury(addressService.getTreasuryAddress());
        reserveService = IReserveService(addressService.getReserveServiceAddress());
        userReserveDataService = IUserReserveDataService(addressService.getUserReserveDataServiceAddress());
        feeService = IFeeService(addressService.getFeeServiceAddress());
        dataQueryService = IDataQueryService(addressService.getDataQueryServiceAddress());
    }
}
