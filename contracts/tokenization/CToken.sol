// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '../libraries/ERC20.sol';

import '../configuration/LendingPoolAddressesProvider.sol';
import '../lendingpool/LendingPool.sol';
import '../lendingpool/LendingPoolDataProvider.sol';
import '../lendingpool/LendingPoolCore.sol';
import '../libraries/WadRayMath.sol';

/**
 * @title CORE interest bearing liquidty pool ERC20
 */

contract CToken is ERC20 {
    using WadRayMath for uint256;

    uint256 public constant UINT_MAX_VALUE = uint256(-1);

    event Redeem(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    event MintOnDeposit(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    event BurnOnLiquidation(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    event BalanceTransfer(
        address indexed _from,
        address indexed _to,
        uint256 _value,
        uint256 _fromBalanceIncrease,
        uint256 _toBalanceIncrease,
        uint256 _fromIndex,
        uint256 _toIndex
    );

    address public underlyingAssetAddress;

    mapping(address => uint256) private userIndexes;

    LendingPoolAddressesProvider private addressesProvider;
    LendingPoolCore private core;
    LendingPool private pool;
    LendingPoolDataProvider private dataProvider;

    modifier onlyLendingPool {
        require(msg.sender == address(pool), 'The caller of this function must be a lending pool');
        _;
    }

    modifier whenTransferAllowed(address _from, uint256 _amount) {
        require(isTransferAllowed(_from, _amount), 'Transfer cannot be allowed.');
        _;
    }

    constructor(
        LendingPoolAddressesProvider _addressesProvider,
        address _underlyingAsset,
        uint8 _underlyingAssetDecimals,
        string memory _name,
        string memory _symbol
    ) public ERC20(_name, _symbol) {
        addressesProvider = _addressesProvider;
        core = LendingPoolCore(addressesProvider.getLendingPoolCore());
        pool = LendingPool(addressesProvider.getLendingPool());
        dataProvider = LendingPoolDataProvider(addressesProvider.getLendingPoolDataProvider());
        underlyingAssetAddress = _underlyingAsset;
    }

    /**
     * @notice ERC20 implementation internal function backing transfer() and transferFrom()
     * @dev validates the transfer before allowing it. NOTE: This is not standard ERC20 behavior
     **/
    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override whenTransferAllowed(_from, _amount) {
        executeTransferInternal(_from, _to, _amount);
    }

    /**
     * @dev redeems cToken for the underlying asset
     * @param _amount the amount being redeemed
     **/
    function redeem(uint256 _amount) external {
        require(_amount > 0, 'Amount to redeem needs to be > 0');

        //cumulates the balance of the user
        (, uint256 currentBalance, uint256 balanceIncrease, uint256 index) = cumulateBalanceInternal(msg.sender);

        uint256 amountToRedeem = _amount;

        //if amount is equal to uint(-1), the user wants to redeem everything
        if (_amount == UINT_MAX_VALUE) {
            amountToRedeem = currentBalance;
        }

        require(amountToRedeem <= currentBalance, 'User cannot redeem more than the available balance');

        //check that the user is allowed to redeem the amount
        require(isTransferAllowed(msg.sender, amountToRedeem), 'Transfer cannot be allowed.');

        // burns tokens equivalent to the amount requested
        _burn(msg.sender, amountToRedeem);

        bool userIndexReset = false;
        //reset the user data if the remaining balance is 0
        if (currentBalance.sub(amountToRedeem) == 0) {
            userIndexReset = resetDataOnZeroBalanceInternal(msg.sender);
        }

        // executes redeem of the underlying asset
        pool.redeemUnderlying(underlyingAssetAddress, msg.sender, amountToRedeem, currentBalance.sub(amountToRedeem));

        emit Redeem(msg.sender, amountToRedeem, balanceIncrease, userIndexReset ? 0 : index);
    }

    /**
     * @dev mints token in the event of users depositing the underlying asset into the lending pool
     * only lending pools can call this function
     * @param _account the address receiving the minted tokens
     * @param _amount the amount of tokens to mint
     */
    function mintOnDeposit(address _account, uint256 _amount) external onlyLendingPool {
        //cumulates the balance of the user
        (, , uint256 balanceIncrease, uint256 index) = cumulateBalanceInternal(_account);

        //mint an equivalent amount of tokens to cover the new deposit
        _mint(_account, _amount);

        emit MintOnDeposit(_account, _amount, balanceIncrease, index);
    }

    /**
     * @dev burns token in the event of a borrow being liquidated, in case the liquidators reclaims the underlying asset
     * Transfer of the liquidated asset is executed by the lending pool contract.
     * only lending pools can call this function
     * @param _account the address from which burn the cTokens
     * @param _value the amount to burn
     **/
    function burnOnLiquidation(address _account, uint256 _value) external onlyLendingPool {
        //cumulates the balance of the user being liquidated
        (, uint256 accountBalance, uint256 balanceIncrease, uint256 index) = cumulateBalanceInternal(_account);

        //burns the requested amount of tokens
        _burn(_account, _value);

        bool userIndexReset = false;
        //reset the user data if the remaining balance is 0
        if (accountBalance.sub(_value) == 0) {
            userIndexReset = resetDataOnZeroBalanceInternal(_account);
        }

        emit BurnOnLiquidation(_account, _value, balanceIncrease, userIndexReset ? 0 : index);
    }

    /**
     * @dev transfers tokens in the event of a borrow being liquidated, in case the liquidators reclaims the cToken
     *      only lending pools can call this function
     * @param _from the address from which transfer the cTokens
     * @param _to the destination address
     * @param _value the amount to transfer
     **/
    function transferOnLiquidation(
        address _from,
        address _to,
        uint256 _value
    ) external onlyLendingPool {
        //being a normal transfer, the Transfer() and BalanceTransfer() are emitted
        //so no need to emit a specific event here
        executeTransferInternal(_from, _to, _value);
    }

    function balanceOf(address _user) public override view returns (uint256) {
        //current principal balance of the user
        uint256 currentPrincipalBalance = super.balanceOf(_user);

        if (currentPrincipalBalance == 0) {
            return 0;
        }

        return calculateCumulatedBalanceInternal(_user, currentPrincipalBalance);
    }

    /**
     * @dev returns the principal balance of the user. The principal balance is the last
     * updated stored balance, which does not consider the perpetually accruing interest.
     * @param _user the address of the user
     * @return the principal balance of the user
     **/
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @dev calculates the total supply of the specific cToken
     * since the balance of every single user increases over time, the total supply
     * does that too.
     * @return the current total supply
     **/
    function totalSupply() public override view returns (uint256) {
        uint256 currentSupplyPrincipal = super.totalSupply();

        if (currentSupplyPrincipal == 0) {
            return 0;
        }

        return
            currentSupplyPrincipal
                .wadToRay()
                .rayMul(core.getReserveNormalizedIncome(underlyingAssetAddress))
                .rayToWad();
    }

    /**
     * @dev Used to validate transfers before actually executing them.
     * @param _user address of the user to check
     * @param _amount the amount to check
     * @return true if the _user can transfer _amount, false otherwise
     **/
    function isTransferAllowed(address _user, uint256 _amount) public view returns (bool) {
        return dataProvider.balanceDecreaseAllowed(underlyingAssetAddress, _user, _amount);
    }

    /**
     * @dev returns the last index of the user, used to calculate the balance of the user
     * @param _user address of the user
     * @return the last user index
     **/
    function getUserIndex(address _user) external view returns (uint256) {
        return userIndexes[_user];
    }

    /**
     * @dev accumulates the accrued interest of the user to the principal balance
     * @param _user the address of the user for which the interest is being accumulated
     * @return the previous principal balance, the new principal balance, the balance increase
     * and the new user index
     **/
    function cumulateBalanceInternal(address _user)
        internal
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 previousPrincipalBalance = super.balanceOf(_user);

        //calculate the accrued interest since the last accumulation
        uint256 balanceIncrease = balanceOf(_user).sub(previousPrincipalBalance);
        //mints an amount of tokens equivalent to the amount accumulated
        _mint(_user, balanceIncrease);
        //updates the user index
        uint256 index = userIndexes[_user] = core.getReserveNormalizedIncome(underlyingAssetAddress);
        return (previousPrincipalBalance, previousPrincipalBalance.add(balanceIncrease), balanceIncrease, index);
    }

    /**
     * @dev calculate the interest accrued by _user on a specific balance
     * @param _user the address of the user for which the interest is being accumulated
     * @param _balance the balance on which the interest is calculated
     * @return the interest rate accrued
     **/
    function calculateCumulatedBalanceInternal(address _user, uint256 _balance) internal view returns (uint256) {
        return
            _balance
                .wadToRay()
                .rayMul(core.getReserveNormalizedIncome(underlyingAssetAddress))
                .rayDiv(userIndexes[_user])
                .rayToWad();
    }

    /**
     * @dev executes the transfer of cTokens, invoked by both _transfer() and
     *      transferOnLiquidation()
     * @param _from the address from which transfer the cTokens
     * @param _to the destination address
     * @param _value the amount to transfer
     **/
    function executeTransferInternal(
        address _from,
        address _to,
        uint256 _value
    ) internal {
        require(_value > 0, 'Transferred amount needs to be greater than zero');

        //cumulate the balance of the sender
        (, uint256 fromBalance, uint256 fromBalanceIncrease, uint256 fromIndex) = cumulateBalanceInternal(_from);

        //cumulate the balance of the receiver
        (, , uint256 toBalanceIncrease, uint256 toIndex) = cumulateBalanceInternal(_to);

        //performs the transfer
        super._transfer(_from, _to, _value);

        bool fromIndexReset = false;
        //reset the user data if the remaining balance is 0
        if (fromBalance.sub(_value) == 0) {
            fromIndexReset = resetDataOnZeroBalanceInternal(_from);
        }

        emit BalanceTransfer(
            _from,
            _to,
            _value,
            fromBalanceIncrease,
            toBalanceIncrease,
            fromIndexReset ? 0 : fromIndex,
            toIndex
        );
    }

    function resetDataOnZeroBalanceInternal(address _user) internal returns (bool) {
        userIndexes[_user] = 0;
        return true;
    }
}
