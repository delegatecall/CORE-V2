// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import './CORELoan.sol';

contract CORELoanFactoryUpgradeTest is Initializable, OwnableUpgradeSafe {
    address public CORE;
    address public loanServiceAddress;
    address[] public allLoans;
}
