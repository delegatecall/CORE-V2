// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

// import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

// import '../configuration/LendingPoolAddressesProvider.sol';
// import '../libraries/CoreLibrary.sol';
// import './LendingPoolCore.sol';
// import './LendingPoolDataProvider.sol';
// import '../libraries/EthAddressLib.sol';

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol';

import '../libraries/WadRayMath.sol';

import '../interfaces/ILendingPoolFacade.sol';
import '../interfaces/ILendingPoolAddressService.sol';
import '../interfaces/ILendingPoolUserLoanDataService.sol';
import '../interfaces/ILendingPoolReserveService.sol';
import '../interfaces/ILendingPoolTreasury.sol';
import '../interfaces/ICToken.sol';

/**
 * @title CORE Lending Pool Facade contract
 * @notice Implements the Lending related actions
 * @author CORE
 **/

contract LendingPoolFacade is ILendingPoolFacade, Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using Address for address;

    ILendingPoolAddressService public AddressService;
    ILendingPoolTreasury private treasury;
    ILendingPoolReserveService private reserveService;
    ILendingPoolUserLoanDataService private userLoanDataService;

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

    function initialize(ILendingPoolAddressService _AddressService) public initializer onlyOwner {
        OwnableUpgradeSafe.__Ownable_init();
        AddressService = _AddressService;
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

        reserveService.updateStateOnDeposit(_reserve, msg.sender, _amount, isFirstDeposit);

        //minting CToken to user 1:1 with the specific exchange rate
        ICToken(cToken).mintOnDeposit(msg.sender, _amount);

        //transfer to the core contract
        treasury.transferToTreasury{value: msg.value}(_reserve, msg.sender, _amount);

        //solium-disable-next-line
        emit Deposit(_reserve, msg.sender, _amount, _referralCode, block.timestamp);
    }

    function refreshConfigInternal() internal {
        treasury = ILendingPoolTreasury(AddressService.getLendingPoolTreasuryAddress());
        reserveService = ILendingPoolReserveService(AddressService.getLendingPoolReserveServiceAddress());
        userLoanDataService = ILendingPoolUserLoanDataService(
            AddressService.getLendingPoolUserLoanDataServiceAddress()
        );
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
}
