// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

interface ILendingPoolFacade {
    /**
     * @dev deposits The underlying asset into the reserve. A corresponding amount of the overlying asset (cTokens)
     * is minted.
     * @param _reserve the address of the reserve
     * @param _amount the amount to be deposited
     * @param _referralCode integrators are assigned a referral code and can potentially receive rewards.
     **/
    function deposit(
        address _reserve,
        uint256 _amount,
        uint16 _referralCode
    ) external payable {}

    /**
     * @dev Redeems the underlying amount of assets requested by _user.
     * This function is executed by the overlying cToken contract in response to a redeem action.
     * @param _reserve the address of the reserve
     * @param _user the address of the user performing the action
     * @param _amount the underlying amount to be redeemed
     **/
    function redeemUnderlying(
        address _reserve,
        address payable _user,
        uint256 _amount,
        uint256 _cTokenBalanceAfterRedeem
    ) external {}

    /**
     * @dev Allows users to borrow a specific amount of the reserve currency, provided that the borrower
     * already deposited enough collateral.
     * @param _reserve the address of the reserve
     * @param _amount the amount to be borrowed
     **/
    function borrow(
        address _reserve,
        uint256 _amount,
        uint16 _referralCode
    ) external {}

    /**
     * @notice repays a borrow on the specific reserve, for the specified amount (or for the whole amount, if uint256(-1) is specified).
     * @dev the target user is defined by _onBehalfOf. If there is no repayment on behalf of another account,
     * _onBehalfOf must be equal to msg.sender.
     * @param _reserve the address of the reserve on which the user borrowed
     * @param _amount the amount to repay, or uint256(-1) if the user wants to repay everything
     * @param _onBehalfOf the address for which msg.sender is repaying.
     **/
    function repay(
        address _reserve,
        uint256 _amount,
        address payable _onBehalfOf
    ) external payable {}

    /**
     * @dev allows depositors to enable or disable a specific deposit as collateral.
     * @param _reserve the address of the reserve
     * @param _useAsCollateral true if the user wants to user the deposit as collateral, false otherwise.
     **/
    function setUserUseReserveAsCollateral(address _reserve, bool _useAsCollateral) external {}

    /**
     * @dev users can invoke this function to liquidate an undercollateralized position.
     * @param _reserve the address of the collateral to liquidated
     * @param _reserve the address of the principal reserve
     * @param _user the address of the borrower
     * @param _purchaseAmount the amount of principal that the liquidator wants to repay
     * @param _receiveCToken true if the liquidators wants to receive the cTokens, false if
     * he wants to receive the underlying asset directly
     **/
    function liquidationCall(
        address _collateral,
        address _reserve,
        address _user,
        uint256 _purchaseAmount,
        bool _receiveCToken
    ) external payable onlyActiveReserve(_reserve) onlyActiveReserve(_collateral) {}
}
