// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @title this is the treasury vault to store all assets in CORE lending system
 */
interface ILendingPoolTreasury {
    function transferToUser(
        address _reserve,
        address payable _user,
        uint256 _amount
    ) external;

    function transferToFeeCollectionAddress(
        address _token,
        address _user,
        uint256 _amount,
        address _destination
    ) external;

    function transferToTreasury(
        address _reserve,
        address payable _user,
        uint256 _amount
    ) external payable;
}
