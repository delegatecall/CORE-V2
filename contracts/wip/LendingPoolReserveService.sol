// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol';

import '../libraries/WadRayMath.sol';
import '../libraries/ReserveDataLibrary.sol';
import '../libraries/EthAddressLib.sol';

import '../interfaces/ILendingPoolFacade.sol';
import '../interfaces/ILendingPoolAddressService.sol';
import '../interfaces/ILendingPoolReserveService.sol';

/**
 * @title This provides necessary methods to update and query reserve status
 */
contract LendingPoolReserveService is ILendingPoolReserveService, Initializable, OwnableUpgradeSafe {
    using ReserveDataLibrary for ReserveDataLibrary.ReserveData;
    using SafeMath for uint256;
    /**
     * @dev Emitted when the state of a reserve is updated
     * @param reserve the address of the reserve
     * @param liquidityRate the new liquidity rate
     * @param variableBorrowRate the new variable borrow rate
     * @param liquidityIndex the new liquidity index
     * @param variableBorrowIndex the new variable borrow index
     **/
    event ReserveUpdated(
        address indexed reserve,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex
    );

    address[] public reservesList;

    mapping(address => ReserveDataLibrary.ReserveData) internal reserves;

    ILendingPoolAddressService private addressService;
    ILendingPoolFacade private poolFacade;

    function initialize(ILendingPoolAddressService _addressService) public initializer onlyOwner {
        OwnableUpgradeSafe.__Ownable_init();
        addressService = _addressService;
        refreshConfigInternal();
    }

    function updateStateOnDeposit(
        address _reserve,
        address _user,
        uint256 _amount
    ) external override {
        reserves[_reserve].updateCumulativeIndexes();
        updateReserveInterestRatesAndTimestampInternal(_reserve, _amount, 0);
    }

    function updateStateOnRedeem(
        address _reserve,
        address _user,
        uint256 _amountRedeemed,
        bool _userRedeemedEverything
    ) external override {}

    function updateStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _amountBorrowed,
        uint256 _borrowFee
    ) external override returns (uint256, uint256) {
        return (0, 0);
    }

    function updateStateOnRepay(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _originationFeeRepaid,
        uint256 _balanceIncrease,
        bool _repaidWholeLoan
    ) external override {}

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
    ) external override {}

    function getReserveIsActive(address _reserve) external override returns (bool) {
        return true;
    }

    function getReserveOverlyingTokenAddress(address _reserve) external override returns (address) {
        return address(0);
    }

    function getReserveNormalizedIncome(address _reserve) external override view returns (uint256) {
        return 0;
    }

    /**
     * @dev gets the available liquidity in the reserve. The available liquidity is the balance of the core contract
     * @param _reserve the reserve address
     * @return the available liquidity
     **/
    function getReserveAvailableLiquidity(address _reserve) public override view returns (uint256) {
        uint256 balance = 0;

        if (_reserve == EthAddressLib.ethAddress()) {
            balance = address(this).balance;
        } else {
            balance = IERC20(_reserve).balanceOf(address(this));
        }
        return balance;
    }

    /**
     * @dev gets the total liquidity in the reserve. The total liquidity is the balance of the core contract + total borrows
     * @param _reserve the reserve address
     * @return the total liquidity
     **/
    function getReserveTotalLiquidity(address _reserve) public view returns (uint256) {
        ReserveDataLibrary.ReserveData storage reserve = reserves[_reserve];
        return getReserveAvailableLiquidity(_reserve).add(reserve.getTotalBorrows());
    }

    function getReserveIsBorrowingEnabled(address _reserve) external override returns (bool) {
        return true;
    }

    function refreshConfigInternal() internal {
        poolFacade = ILendingPoolFacade(addressService.getLendingPoolFacadeAddress());
    }

    /**
     * @dev Updates the reserve current stable borrow rate Rf, the current variable borrow rate Rv and the current liquidity rate Rl.
     * Also updates the lastUpdateTimestamp value. Please refer to the whitepaper for further information.
     * @param _reserve the address of the reserve to be updated
     * @param _liquidityAdded the amount of liquidity added to the protocol (deposit or repay) in the previous action
     * @param _liquidityTaken the amount of liquidity taken from the protocol (redeem or borrow)
     **/

    function updateReserveInterestRatesAndTimestampInternal(
        address _reserve,
        uint256 _liquidityAdded,
        uint256 _liquidityTaken
    ) internal {
        ReserveDataLibrary.ReserveData storage reserve = reserves[_reserve];

        // hardcode varible interest rate
        uint256 newVariableRate = 0.05 * 1e27;
        uint256 newLiquidityRate = 10;
        reserve.currentLiquidityRate = newLiquidityRate;
        reserve.currentVariableBorrowRate = newVariableRate;

        //solium-disable-next-line
        reserve.lastUpdateTimestamp = uint40(block.timestamp);

        emit ReserveUpdated(
            _reserve,
            newLiquidityRate,
            newVariableRate,
            reserve.lastLiquidityCumulativeIndex,
            reserve.lastVariableBorrowCumulativeIndex
        );
    }
}
