// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import './libraries/WadRayMath.sol';
import './Treasury.sol';
import './PriceOracle.sol';
import 'hardhat/console.sol';

contract CORELoan is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    event Borrow(address indexed _user, uint256 _borrowBalance, uint256 _borrowRate, uint256 _timestamp);

    event Repay(
        address indexed _repayer,
        uint256 _principalPayment,
        uint256 _interestPayment,
        uint256 _coreReturned,
        uint256 _timestamp
    );

    event LiquidationCall(address indexed _user, address _liquidator, uint256 _purchaseAmount, uint256 _timestamp);

    address constant CORE_ADDRESS = 0x62359Ed7505Efc61FF1D56fEF82158CcaffA23D7;

    uint256 constant YEAR_IN_SECONDS = 365 days;

    uint256 constant LIQUIDATION_BONUSE = 8;

    struct EthReserveData {
        uint256 totalBorrow;
        uint256 variableBorrowRate; // rate in ray
        uint256 variableBorrowCumulativeIndex; //in ray
        uint256 liquidationThreshold;
        uint256 lastUpdateTimestamp;
    }

    struct CORELoanData {
        uint256 coreAmount;
        uint256 principalBorrowBalance;
        uint256 accuredInterest;
        uint256 variableBorrowCumulativeIndex; // in ray
        uint256 lastUpdateTimestamp;
    }

    PriceOracle public priceOracle;
    Treasury public treasury;
    EthReserveData private ethReserveData;

    mapping(address => CORELoanData) private userCORELoanData;

    function initialize() public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        ethReserveData.variableBorrowRate = uint256(5).mul(WadRayMath.ray());
        ethReserveData.variableBorrowCumulativeIndex = WadRayMath.ray();
        ethReserveData.liquidationThreshold = 75;
        ethReserveData.lastUpdateTimestamp = block.timestamp;
    }

    function setAddresses(PriceOracle _priceOracle, Treasury _treasury) external onlyOwner {
        priceOracle = _priceOracle;
        treasury = _treasury;
    }

    function getEthReserveData()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            ethReserveData.totalBorrow,
            ethReserveData.variableBorrowRate,
            ethReserveData.variableBorrowCumulativeIndex,
            ethReserveData.liquidationThreshold,
            ethReserveData.lastUpdateTimestamp
        );
    }

    function getUserLoanInfo(address _user)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        CORELoanData storage loanData = userCORELoanData[_user];

        if (loanData.principalBorrowBalance == 0) {
            return (0, 0, 0, 0);
        }

        uint256 cumulatedVariableBorrowInterest = calculateCompoundedInterest(
            ethReserveData.variableBorrowRate,
            ethReserveData.lastUpdateTimestamp
        );

        uint256 ethReserveCumulativeIndexAsForNow = cumulatedVariableBorrowInterest.rayMul(
            ethReserveData.variableBorrowCumulativeIndex
        );

        uint256 totalOwned = loanData.principalBorrowBalance.add(loanData.accuredInterest).wadToRay();

        uint256 newlyAccuredInterest = totalOwned
            .rayMul(ethReserveCumulativeIndexAsForNow)
            .rayDiv(loanData.variableBorrowCumulativeIndex)
            .sub(totalOwned)
            .rayToWad();
        console.log(
            'reserveindex',
            totalOwned,
            ethReserveCumulativeIndexAsForNow,
            loanData.variableBorrowCumulativeIndex
        );
        uint256 coreEthPrice = priceOracle.getCOREPrice();

        return (
            loanData.principalBorrowBalance,
            loanData.accuredInterest.add(newlyAccuredInterest),
            loanData.coreAmount,
            coreEthPrice
        );
    }

    function borrow(uint256 _coreAmount) external {
        uint256 bottomPrice = priceOracle.getCOREBottomPrice();
        uint256 newBorrow = _coreAmount.wadMul(bottomPrice);
        updateEthReserveCumulativeIndex();
        updateEthReserveBalanceAndInterestRate(newBorrow, 0);
        updateUserCORELoanDataOnBorrow(_coreAmount, newBorrow);
        //TODO enable transfer after configuring live testing
        // treasury.transferEthToUser(msg.sender, newBorrow);
        // safeTransfer(CORE_ADDRESS, treasury, _coreAmount);
        emit Borrow(msg.sender, newBorrow, ethReserveData.variableBorrowRate, block.timestamp);
    }

    function repay(uint256 _payment) external payable {
        require(msg.value > _payment, 'not enough eth');

        updateEthReserveCumulativeIndex();
        updateEthReserveBalanceAndInterestRate(0, _payment);
        (uint256 principalPayment, uint256 interestPayment, uint256 coreReturned) = updateUserCORELoanDataOnRepay(
            msg.sender,
            _payment,
            0
        );

        treasury.receivePayment{value: principalPayment.add(interestPayment)}(principalPayment, interestPayment);

        treasury.transferCOREToUser(msg.sender, coreReturned);

        if (msg.value > principalPayment.add(interestPayment)) {
            //refund for excess money
            safeTransferEth(msg.sender, msg.value.sub(principalPayment).sub(interestPayment));
        }

        emit Repay(msg.sender, principalPayment, interestPayment, coreReturned, block.timestamp);
    }

    function liquidationCall(address _user, uint256 _purchaseAmount) external payable {
        (uint256 principalBalance, uint256 accuredInterest, uint256 coreAmount, uint256 coreEthPrice) = getUserLoanInfo(
            _user
        );

        require(principalBalance > 0, 'no loan yet');

        require(
            principalBalance.add(accuredInterest).div(coreAmount.mul(coreEthPrice)).mul(100) <=
                ethReserveData.liquidationThreshold,
            'user loan is healthy. invalid liquidation call'
        );

        uint256 maximumAllowedLiquidationAmount = coreAmount.mul(50).div(100);

        if (_purchaseAmount > maximumAllowedLiquidationAmount) {
            _purchaseAmount = maximumAllowedLiquidationAmount;
        }

        // give the caller 10% discount as reward

        uint256 discountedCOREEthPrice = coreEthPrice.mul(LIQUIDATION_BONUSE).div(100);

        uint256 totalEthRequired = discountedCOREEthPrice.wadMul(_purchaseAmount);

        require(msg.value >= totalEthRequired, 'no enough eth to purchase core');

        updateEthReserveCumulativeIndex();
        updateEthReserveBalanceAndInterestRate(0, totalEthRequired);

        (uint256 principalPayment, uint256 interestPayment, uint256 coreReturned) = updateUserCORELoanDataOnRepay(
            _user,
            totalEthRequired,
            _purchaseAmount
        );

        assert(coreReturned == _purchaseAmount);

        uint256 totalPayment = principalPayment.add(interestPayment);

        treasury.transferCOREToUser(msg.sender, coreReturned);
        if (totalEthRequired > totalPayment) {
            safeTransferEth(_user, totalEthRequired.sub(totalPayment));
        }

        if (msg.value > totalEthRequired) {
            safeTransferEth(msg.sender, msg.value.sub(totalEthRequired));
        }

        emit LiquidationCall(_user, msg.sender, _purchaseAmount, block.timestamp);
    }

    function updateEthReserveCumulativeIndex() internal {
        uint256 cumulatedVariableBorrowInterest = calculateCompoundedInterest(
            ethReserveData.variableBorrowRate,
            ethReserveData.lastUpdateTimestamp
        );

        ethReserveData.variableBorrowCumulativeIndex = cumulatedVariableBorrowInterest.rayMul(
            ethReserveData.variableBorrowCumulativeIndex
        );
        ethReserveData.lastUpdateTimestamp = block.timestamp;

        // TODOmake it simple for now, fixed 5% interest rate
    }

    function updateEthReserveBalanceAndInterestRate(uint256 _newBorrow, uint256 _payment) internal {
        ethReserveData.totalBorrow = ethReserveData.totalBorrow.add(_newBorrow).sub(_payment);

        // TODO for now, interest rate is not adjusted based on totalBorrow, so do nothing
    }

    function updateUserCORELoanDataOnBorrow(uint256 _amount, uint256 _newBorrow) internal {
        updateUserLoanAccuredInterestAndCumulativeIndex();
        CORELoanData storage loanData = userCORELoanData[msg.sender];

        loanData.principalBorrowBalance += _newBorrow;
        loanData.coreAmount += _amount;
    }

    function updateUserCORELoanDataOnRepay(
        address _user,
        uint256 _payment,
        uint256 _coreAmount
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 principalPayment;
        uint256 interestPayment;
        uint256 coreReturned;

        CORELoanData storage loanData = userCORELoanData[_user];

        require(loanData.principalBorrowBalance > 0, 'no loan to replay');

        updateUserLoanAccuredInterestAndCumulativeIndex();

        if (_payment > loanData.accuredInterest) {
            uint256 paymentAfterInterest = _payment.sub(loanData.accuredInterest);
            interestPayment = loanData.accuredInterest;
            loanData.accuredInterest = 0;

            if (paymentAfterInterest > loanData.principalBorrowBalance) {
                principalPayment = loanData.principalBorrowBalance;

                if (_coreAmount > 0) {
                    coreReturned = _coreAmount;
                } else {
                    coreReturned = loanData.coreAmount;
                }
            } else {
                principalPayment = paymentAfterInterest;
                if (_coreAmount > 0) {
                    coreReturned = _coreAmount;
                } else {
                    coreReturned = paymentAfterInterest.div(loanData.principalBorrowBalance).sub(loanData.coreAmount);
                }
            }
        } else {
            loanData.accuredInterest = loanData.accuredInterest - _payment;

            interestPayment = _payment;
        }

        loanData.principalBorrowBalance -= principalPayment;
        loanData.coreAmount -= coreReturned;

        // reset loandata if the loan is fully repayed

        if (loanData.principalBorrowBalance == 0) {
            loanData.lastUpdateTimestamp = 0;
            loanData.variableBorrowCumulativeIndex = 0;
        }

        return (principalPayment, interestPayment, coreReturned);
    }

    function updateUserLoanAccuredInterestAndCumulativeIndex() internal {
        CORELoanData storage loanData = userCORELoanData[msg.sender];

        if (loanData.principalBorrowBalance > 0) {
            uint256 totalOwned = loanData.principalBorrowBalance.add(loanData.accuredInterest).wadToRay();

            uint256 newlyAccuredInterest = totalOwned
                .rayMul(ethReserveData.variableBorrowCumulativeIndex)
                .rayDiv(loanData.variableBorrowCumulativeIndex)
                .sub(totalOwned)
                .rayToWad();

            loanData.accuredInterest = loanData.accuredInterest.add(newlyAccuredInterest);
        }

        loanData.lastUpdateTimestamp == block.timestamp;
        loanData.variableBorrowCumulativeIndex = ethReserveData.variableBorrowCumulativeIndex;
    }

    function calculateCompoundedInterest(uint256 _rate, uint256 _lastUpdateTimestamp) internal view returns (uint256) {
        //solium-disable-next-line
        uint256 timeDifference = block.timestamp.sub(_lastUpdateTimestamp);

        uint256 ratePerSecond = _rate.div(YEAR_IN_SECONDS);

        return ratePerSecond.add(WadRayMath.ray()).rayPow(timeDifference);
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'LGE3: TRANSFER_FAILED');
    }

    function safeTransferEth(address _to, uint256 value) internal {
        (bool result, ) = _to.call{value: value}('');
        require(result, 'Transfer of ETH failed');
    }
}
