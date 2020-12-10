// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @title this is CORE Lending Pool Aggegrated Data Query Service.
 * @dev this is the Query part of CQRS, LendPoolFacade is the Command Part
 */

interface IDataQueryService {
    /**
     * @dev check if a specific balance decrease is allowed (i.e. doesn't bring the user borrow position health factor under 1e18)
     * @param _reserve the address of the reserve
     * @param _user the address of the user
     * @param _amount the amount to decrease
     * @return true if the decrease of the balance is allowed
     **/
    function getBalanceDecreaseIsAllowed(
        address _reserve,
        address _user,
        uint256 _amount
    ) external view returns (bool);

    function getBorrowIsBackedByEnoughCollateral(
        address _reserve,
        address _user,
        uint256 _amount
    ) external view returns (bool);

    function getUserBorrowBalances(address _reserve, address _user)
        external
        view
        returns (uint256 principalBorrowBalance, uint256 cumulativeBorrowBalance);
}
