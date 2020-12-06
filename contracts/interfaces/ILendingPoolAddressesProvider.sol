// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
@title ILendingPoolAddressesProvider interface
@notice provides the interface to fetch the LendingPoolCore address
 */

interface ILendingPoolAddressesProvider {
    function getLendingPool() external virtual view returns (address);

    function getLendingPoolCore() external virtual view returns (address payable);

    function getLendingPoolDataProvider() external virtual view returns (address);

    function getPriceOracle() external virtual view returns (address);
}
