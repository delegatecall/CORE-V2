// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '../libraries/WadRayMath.sol';
import '../interfaces/IPriceOracle.sol';

contract PriceOracle is IPriceOracle {
    function getCoreEthBottomPriceInRay() external override view returns (uint256) {
        return WadRayMath.ray();
    }
}
