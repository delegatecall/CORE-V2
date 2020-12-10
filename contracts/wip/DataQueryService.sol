// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import '../libraries/WadRayMath.sol';

import '../interfaces/IPriceOracle.sol';
import '../interfaces/IAddressService.sol';
import '../interfaces/IUserReserveDataService.sol';
import '../interfaces/IReserveService.sol';
import '../interfaces/IDataQueryService.sol';
import '../interfaces/ICToken.sol';

/**
 * @title CORE Lending Pool Facade contract
 * @notice Implements the Lending related actions
 * @author CORE
 **/

contract DataQueryService is IDataQueryService, Initializable, OwnableUpgradeSafe {
    using WadRayMath for uint256;
    IAddressService public addressService;
    IReserveService private reserveService;
    IUserReserveDataService private userReserveDataService;
    IPriceOracle private priceOracle;

    function initialize(IAddressService _addressService) public initializer onlyOwner {
        OwnableUpgradeSafe.__Ownable_init();
        addressService = _addressService;
        refreshConfigInternal();
    }

    function getBalanceDecreaseIsAllowed(
        address _reserve,
        address _user,
        uint256 _amount
    ) external override view returns (bool) {
        return true;
    }

    function getBorrowIsBackedByEnoughCollateral(
        address _reserve,
        address _user,
        uint256 _amount
    ) external override view returns (bool) {
        return true;
    }

    /**
     * @dev calculates and returns the borrow balances of the user
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     **/
    function getUserBorrowBalances(address _reserve, address _user)
        public
        override
        view
        returns (uint256 principalBorrowBalance, uint256 cumulativeBorrowBalance)
    {
        uint256 lastVariableBorrowCumulativeIndex;
        (principalBorrowBalance, lastVariableBorrowCumulativeIndex, ) = userReserveDataService.getUserReserveData(
            _reserve,
            msg.sender
        );

        uint256 currentCumulativeVariableRate = reserveService.getReserveNormalizedVariableRate(_reserve);

        cumulativeBorrowBalance = principalBorrowBalance.wadToRay().rayMul(currentCumulativeVariableRate).rayDiv(
            lastVariableBorrowCumulativeIndex
        );
    }

    function refreshConfigInternal() internal {}
}
