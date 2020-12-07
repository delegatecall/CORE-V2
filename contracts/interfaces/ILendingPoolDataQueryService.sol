// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @title this is CORE Lending Pool Aggegrated Data Query Service.
 * @dev this is the Query part of CQRS, LendPoolFacade is the Command Part
 */

interface ILendingPoolDataQueryService {
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

    /**
     * @dev calculates the user data across the reserves.
     * @param _user the address of the user
     **/
    function calculateUserGlobalData(address _user)
        external
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
        );

    /**
     * @notice calculates the amount of collateral needed in ETH to cover a new borrow.
     * @param _reserve the reserve from which the user wants to borrow
     * @param _amount the amount the user wants to borrow
     * @param _fee the fee for the amount that the user needs to cover
     * @param _userCurrentBorrowBalanceTH the current borrow balance of the user (before the borrow)
     * @param _userCurrentLtv the average ltv of the user given his current collateral
     * @return  the total amount of collateral in ETH to cover the current borrow balance + the new amount + fee
     **/
    function calculateCollateralNeededInETH(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        uint256 _userCurrentBorrowBalanceTH,
        uint256 _userCurrentFeesETH,
        uint256 _userCurrentLtv
    ) external view returns (uint256);
}
