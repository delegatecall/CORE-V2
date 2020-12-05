// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

contract CORELoan {
    address payable public lender;
    address payable public borrower;

    uint256 public coreAmount;
    uint256 public loanSize;

    uint256 public payoffAmount;
    uint256 public loanDuration;
    uint256 public interestRate;
    uint256 public createdAt;
    uint256 public acceptedAt;
    uint256 public loanDueDate;

    // the days between loan mature and borrow can repossess
    uint256 public gracePeriod = 2 days;

    address public CORE = 0x62359Ed7505Efc61FF1D56fEF82158CcaffA23D7;

    enum LoanStatus {Open, Cancel, Accepted, Paid, Repossessed}
    LoanStatus public loanStatus;

    // ignore the event parameters for the draft version
    event LoanCreated();
    event LoanCancel();
    event LoanAccepted();
    event LoanPaid();
    event LoanRepossessed();

    constructor(
        address payable _borrower,
        uint256 _coreAmount,
        uint256 _loanSize,
        uint256 _loanDuration,
        uint256 _interestRate
    ) public {
        borrower = _borrower;
        coreAmount = _coreAmount;
        loanSize = _loanSize;
        loanDuration = _loanDuration;
        interestRate = _interestRate;

        loanStatus = LoanStatus.Open;

        emit LoanCreated();
    }

    function CancelLoan() public {
        require(msg.sender == borrower);
        require(loanStatus == LoanStatus.Open);

        // TODO transfer core token back to the borrower safely

        loanStatus = LoanStatus.Cancel;
    }

    function AcceptLoan() public payable {
        require(msg.value == loanSize);
        require(loanStatus == LoanStatus.Open);

        acceptedAt = block.timestamp;

        // loanDuration value is checked by the factory contract, assume it is safe to add

        loanDueDate = block.timestamp + loanDuration;
        loanStatus = LoanStatus.Accepted;
        lender = msg.sender;

        emit LoanAccepted();
    }

    function payLoan() public payable {
        require(block.timestamp >= loanDueDate);
        require(block.timestamp <= loanDueDate + gracePeriod);
        require(msg.value == payoffAmount);

        // TODO implement return core to borrower and return eth to leander safely

        loanStatus = LoanStatus.Paid;

        emit LoanPaid();
    }

    function repossess() public {
        require(block.timestamp > loanDueDate + gracePeriod);

        // TODO transfer core to lender safely

        emit LoanRepossessed();
    }
}
