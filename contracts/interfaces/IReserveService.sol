// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @title This provides necessary methods to update and query reserve status
 */
interface IReserveService {
    function updateStateOnDeposit(
        address _reserve,
        address _user,
        uint256 _amount
    ) external;

    function updateStateOnRedeem(
        address _reserve,
        address _user,
        uint256 _amountRedeemed,
        bool _userRedeemedEverything
    ) external;

    function updateStateOnBorrow(
        address _reserve,
        uint256 _amountBorrowed,
        uint256 _borrowFee
    ) external returns (uint256, uint256);

    function updateStateOnRepay(
        address _reserve,
        address _user,
        uint256 _paybackAmountMinusFees,
        uint256 _originationFeeRepaid,
        uint256 _balanceIncrease,
        bool _repaidWholeLoan
    ) external;

    function updateStateOnLiquidation(
        address _principalReserve,
        address _collateralReserve,
        address _user,
        uint256 _amountToLiquidate,
        uint256 _collateralToLiquidate,
        uint256 _feeLiquidated,
        uint256 _liquidatedCollateralForFee,
        uint256 _balanceIncrease,
        bool _liquidatorReceivesCToken
    ) external;

    function getReserveIsActive(address _reserve) external returns (bool);

    function getReserveOverlyingTokenAddress(address _reserve) external returns (address);

    function getReserveNormalizedIncome(address _reserve) external view returns (uint256);

    function getReserveNormalizedVariableRate(address _reserve) external view returns (uint256);

    /**
     * @dev gets the available liquidity in the reserve. The available liquidity is the balance of the core contract
     * @param _reserve the reserve address
     * @return the available liquidity
     **/
    function getReserveAvailableLiquidity(address _reserve) external view returns (uint256);

    function getReserveIsBorrowingEnabled(address _reserve) external returns (bool);
}
