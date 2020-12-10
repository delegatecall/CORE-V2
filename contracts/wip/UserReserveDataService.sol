// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import '../libraries/UserReserveDataLibrary.sol';
import '../libraries/WadRayMath.sol';

import '../interfaces/IUserReserveDataService.sol';
import '../interfaces/IAddressService.sol';
import '../interfaces/IReserveService.sol';
import '../interfaces/IPriceOracle.sol';

/**
 * @title CORE Lending Pool Facade contract
 * @notice Implements the Lending related actions
 * @author CORE
 **/

contract UserReserveDataService is IUserReserveDataService, Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    struct UserReserveData {
        //principal amount borrowed by the user.
        uint256 principalBorrowBalance;
        //cumulated variable borrow index for the user. Expressed in ray
        uint256 lastVariableBorrowCumulativeIndex;
        //origination fee cumulated by the user
        uint256 originationFee;
        // stable borrow rate at which the user has borrowed. Expressed in ray
        uint40 lastUpdateTimestamp;
        //defines if a specific deposit should or not be used as a collateral in borrows
        bool useAsCollateral;
    }

    mapping(address => mapping(address => UserReserveData)) internal usersReserveData;

    IAddressService public addressService;
    IReserveService private reserveService;
    IUserReserveDataService private userReserveDataService;
    IPriceOracle private priceOracle;

    function initialize(IAddressService _addressService) public initializer onlyOwner {
        OwnableUpgradeSafe.__Ownable_init();
        addressService = _addressService;
        refreshConfigInternal();
    }

    function updateStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _balanceIncrease,
        uint256 _lastVariableBorrowCumulativeIndex,
        uint256 _fee
    ) external override {
        UserReserveData storage user = usersReserveData[_user][_reserve];

        user.lastVariableBorrowCumulativeIndex = _lastVariableBorrowCumulativeIndex;
        user.principalBorrowBalance = user.principalBorrowBalance.add(_balanceIncrease);
        user.originationFee = user.originationFee.add(_fee);

        user.lastUpdateTimestamp = uint40(block.timestamp);
    }

    function getUserReserveData(address _reserve, address _user)
        external
        override
        view
        returns (
            uint256 principalBorrowBalance,
            uint256 lastVariableBorrowCumulativeIndex,
            uint256 lastUpdateTimestamp
        )
    {
        UserReserveData storage data = usersReserveData[_reserve][_user];
        return (data.principalBorrowBalance, data.lastVariableBorrowCumulativeIndex, data.lastUpdateTimestamp);
    }

    function enableDepositAsCollateral(address _reserve, address _user) external override {
        UserReserveData storage data = usersReserveData[_reserve][_user];
        data.useAsCollateral = true;
    }

    function getPrincipalBorrowBalance(address _reserve, address _user) external override view returns (uint256) {
        UserReserveData storage data = usersReserveData[_reserve][_user];
        return data.principalBorrowBalance;
    }

    function refreshConfigInternal() internal {}
}
