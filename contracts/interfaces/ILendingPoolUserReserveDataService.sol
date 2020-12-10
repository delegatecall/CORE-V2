// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @title This provides necessary methods to update user resever data
 */
interface ILendingPoolUserReserveDataService {
    function enableDepositAsCollateral(address _reseve, address _user) external;

    function getPrincipalBorrowBalance(address _reserve, address _user) external view returns (uint256);

    function updateStateOnBorrow(
        address _reserve,
        address _user,
        uint256 _balanceIncrease,
        uint256 _lastVariableBorrowCumulativeIndex,
        uint256 _fee
    ) external;

    function getUserReserveData(address _reserve, address _user)
        external
        view
        returns (
            uint256 principalBorrowBalance,
            uint256 lastVariableBorrowCumulativeIndex,
            uint256 lastUpdateTimestamp
        );
}
