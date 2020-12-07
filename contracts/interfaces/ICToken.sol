// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

interface ICToken {
    function mintOnDeposit(address _account, uint256 _amount) external;
}
