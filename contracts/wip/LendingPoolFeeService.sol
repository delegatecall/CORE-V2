// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import '../interfaces/ILendingPoolFeeService.sol';
import '../libraries/WadRayMath.sol';

/**
 * @title FeeProvider contract
 **/
contract FeeProvider is ILendingPoolFeeService, Initializable {
    using WadRayMath for uint256;

    // percentage of the fee to be calculated on the loan amount
    uint256 public originationFeePercentage;

    /**
     * @dev initializes the FeeProvider after it's added to the proxy
     * @param _addressesProvider the address of the LendingPoolAddressesProvider
     */
    function initialize(address _addressesProvider) public initializer {
        /// @notice origination fee is set as default as 25 basis points of the loan amount (0.0025%)
        originationFeePercentage = 0.0025 * 1e18;
    }

    function calculateLoanOriginationFee(address _user, uint256 _amount) external override view returns (uint256) {
        return _amount.wadMul(originationFeePercentage);
    }

    /**
     * @dev returns the origination fee percentage
     **/
    function getLoanOriginationFeePercentage() external override view returns (uint256) {
        return originationFeePercentage;
    }
}
