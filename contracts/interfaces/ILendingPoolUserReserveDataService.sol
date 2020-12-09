// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @title This provides necessary methods to update user resever data
 */
interface ILendingPoolUserReserveDataService {
    function enableDepositAsCollateral(address _resever, address _user) external;
}
