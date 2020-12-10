// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

interface IFeeService {
    function calculateLoanOriginationFee(address _user, uint256 _amount) external view returns (uint256);

    function getLoanOriginationFeePercentage() external view returns (uint256);
}
