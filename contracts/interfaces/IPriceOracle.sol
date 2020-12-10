// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

interface IPriceOracle {
    function getCoreEthBottomPriceInRay() external view returns (uint256);
}
