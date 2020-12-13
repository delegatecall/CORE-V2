// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM
pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

contract PriceOracle is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;

    uint256 private coreBottomPrice;
    uint256 private corePrice;

    function initialize() public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        coreBottomPrice = 2e18;
        corePrice = uint256(6666666).div(1000000).mul(1e18);
    }

    function getCOREBottomPrice() external view returns (uint256) {
        //TODO calculate properyly
        return coreBottomPrice;
    }

    function setCOREBottomPrice(uint256 _price) external onlyOwner {
        coreBottomPrice = _price;
    }

    function getCOREPrice() external view returns (uint256) {
        //TODO calculate based on uni
        return coreBottomPrice;
    }

    function setCOREPrice(uint256 _price) external onlyOwner returns (uint256) {
        corePrice = _price;
    }
}
