// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';


contract LendingPoolAddressesProvider is Initializable, OwnableUpgradeSafe {
    address private lendPool
    address private lendPoolCore
    address private lendPoolDataProvider
    address private priceOracle

    function getLendingPool() public view returns (address) {
        return lendPool;
    }

    function setLendingPool(address _new) public onlyOwner {
        lendPool = _new;
    }

    function getLendingPoolCore() public view returns (address payable) {
        return lendPoolCore;
    }

    function setLendingPoolCore(address _new) public onlyOwner  {
        lendPoolCore = _new;
    }

    function getLendingPoolDataProvider() public view returns (address) {
        return lendPoolDataProviderAddress;
    }

    function setLendingPoolDataProvider (address _new) public onlyOwner  {
        lendPoolDataProvider = _new;
    }

    function getPriceOracle() public view returns (address) {
        return priceOracleAddress;
    }

    function setPriceOracle (address _new) public onlyOwner  {
        priceOracle = _new;
    }
    
}
