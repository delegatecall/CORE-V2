// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol';

import '../libraries/WadRayMath.sol';

library UserReserveDataLibrary {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    enum InterestRateMode {NONE, STABLE, VARIABLE}

    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    struct UserReserveData {
        //principal amount borrowed by the user.
        uint256 principalBorrowBalance;
        //cumulated variable borrow index for the user. Expressed in ray
        uint256 lastVariableBorrowCumulativeIndex;
        //origination fee cumulated by the user
        uint256 originationFee;
        // stable borrow rate at which the user has borrowed. Expressed in ray
        uint40 lastUpdateTimestamp;
        //defines if a specific deposit should or not be used as a collateral in borrows
        bool useAsCollateral;
    }
}
