// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity =0.7.5;
import './CORELoan.sol';

contract CORELoanFactory {
    address[] public allLoans;

    event LoanCreated(address indexed borrower, uint256 sizeInCORE);

    function allLoansLength() external view returns (uint256) {
        return allLoans.length;
    }

    function createLoan(
        address collateral,
        uint256 collateralAmount,
        uint256 ethToBorrow,
        uint256 loanDuration,
        uint256 interestRate
    ) external returns (address loan) {
        require(collateral == 0x62359Ed7505Efc61FF1D56fEF82158CcaffA23D7, 'only support CORE');

        // TODO the validity of all other parameters

        loan = address(new CORELoan(msg.sender, collateralAmount, ethToBorrow, loanDuration, interestRate));
        // TODO transfer CORE to the newly created loan
        allLoans.push(loan);
        emit LoanCreated(msg.sender, collateralAmount);
    }
}
