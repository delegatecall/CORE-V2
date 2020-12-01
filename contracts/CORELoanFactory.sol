// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

import './CORELoan.sol';

interface ICORELoanService {
    function getMaximumEthBorrowing(uint256 coreAmount) external returns (uint256);
}

contract CORELoanFactory is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;

    address public CORE;
    ICORELoanService public coreLoanService;
    address[] public allLoans;

    event LoanCreated(address indexed borrower, uint256 sizeInCORE);

    function initialize(address _loanServiceAddr) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        CORE = 0x62359Ed7505Efc61FF1D56fEF82158CcaffA23D7;
        coreLoanService = ICORELoanService(_loanServiceAddr);
    }

    function allLoansLength() external view returns (uint256) {
        return allLoans.length;
    }

    function createLoan(
        address _collateral,
        uint256 _collateralAmount,
        uint256 _ethBorrowing,
        uint256 _loanDuration, // maybe change to a smaller uint type?
        uint256 _interestRate // maybe change to a smaller uint type?
    ) external returns (address loan) {
        require(_collateral == CORE, 'only support CORE');
        uint256 maxEth = coreLoanService.getMaximumEthBorrowing(_collateralAmount);
        require(_ethBorrowing <= maxEth, 'borrow too much');

        validateInterestRate(_interestRate);
        validateLoanDuration(_loanDuration);
        loan = address(new CORELoan(msg.sender, _collateralAmount, _ethBorrowing, _loanDuration, _interestRate));
        safeTransferFrom(CORE, msg.sender, loan, _collateralAmount);
        allLoans.push(loan);
        emit LoanCreated(msg.sender, _collateralAmount);
    }

    // copy from LGE3 contract
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    // maybe move this to the loanservice contract
    function validateInterestRate(uint256 _interestRate) internal {
        // TODO implement  interest rate validation logic
    }

    // maybe move this to the loanservice contract
    function validateLoanDuration(uint256 _loanDuration) internal {
        // TODO implement  interest rate validation logic
    }
}
