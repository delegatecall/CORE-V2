// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import '../libraries/ERC20.sol';
import '../libraries/WadRayMath.sol';

import '../interfaces/ICToken.sol';
import '../interfaces/IFacade.sol';
import '../interfaces/IAddressService.sol';
import '../interfaces/IReserveService.sol';
import '../interfaces/IDataQueryService.sol';

/**
 * @title CORE interest bearing liquidty pool ERC20
 */

contract CToken is ERC20UpgradeSafe, OwnableUpgradeSafe, ICToken {
    using WadRayMath for uint256;

    uint256 public constant UINT_MAX_VALUE = uint256(-1);

    /**
     * @param _from the address performing the redeem
     * @param _value the amount to be redeemed
     * @param _fromBalanceIncrease the cumulated balance since the last update of the user
     * @param _fromIndex the last index of the user
     **/
    event Redeem(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    /**
     * @param _from the address performing the mint
     * @param _value the amount to be minted
     * @param _fromBalanceIncrease the cumulated balance since the last update of the user
     * @param _fromIndex the last index of the user
     **/
    event MintOnDeposit(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    address public underlyingAssetAddress;

    mapping(address => uint256) private userIndexes;

    IFacade private poolFacade;
    IAddressService private addressService;
    IReserveService private reserveService;
    IDataQueryService private dataQueryService;

    modifier only {
        require(msg.sender == address(poolFacade), 'The caller of this function must be a lending pool');
        _;
    }

    function initialize(
        IAddressService _addressService,
        address _underlyingAsset,
        uint8 _underlyingAssetDecimals,
        string memory _name,
        string memory _symbol
    ) public initializer onlyOwner {
        OwnableUpgradeSafe.__Ownable_init();
        ERC20UpgradeSafe.__ERC20_init(_name, _symbol);
        addressService = _addressService;
        refreshConfigInternal();
    }

    function balanceOf(address _user) public override view returns (uint256) {
        //current principal balance of the user
        uint256 currentPrincipalBalance = super.balanceOf(_user);

        if (currentPrincipalBalance == 0) {
            return 0;
        }

        //accruing for himself means that both the principal balance and
        //the redirected balance partecipate in the interest
        return calculateCumulatedBalanceInternal(_user, currentPrincipalBalance);
    }

    function mintOnDeposit(address _account, uint256 _amount) external override only {
        //cumulates the balance of the user
        (, , uint256 balanceIncrease, uint256 index) = cumulateBalanceInternal(_account);

        //mint an equivalent amount of tokens to cover the new deposit
        _mint(_account, _amount);

        emit MintOnDeposit(_account, _amount, balanceIncrease, index);
    }

    function redeem(uint256 _amount) external override {
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
            userIndexReset = true;
            userIndexes[msg.sender] = 0;
        }

        // executes redeem of the underlying asset
        poolFacade.redeemUnderlying(
            underlyingAssetAddress,
            msg.sender,
            amountToRedeem,
            currentBalance.sub(amountToRedeem)
        );

        emit Redeem(msg.sender, amountToRedeem, balanceIncrease, userIndexReset ? 0 : index);
    }

    function refreshConfigInternal() internal {
        poolFacade = IFacade(addressService.getFacadeAddress());
        reserveService = IReserveService(addressService.getReserveServiceAddress());
        dataQueryService = IDataQueryService(addressService.getDataQueryServiceAddress());
    }

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
        uint256 index = userIndexes[_user] = reserveService.getReserveNormalizedIncome(underlyingAssetAddress);
        return (previousPrincipalBalance, previousPrincipalBalance.add(balanceIncrease), balanceIncrease, index);
    }

    function calculateCumulatedBalanceInternal(address _user, uint256 _balance) internal view returns (uint256) {
        return
            _balance
                .wadToRay()
                .rayMul(reserveService.getReserveNormalizedIncome(underlyingAssetAddress))
                .rayDiv(userIndexes[_user])
                .rayToWad();
    }

    /**
     * @dev Used to validate transfers before actually executing them.
     * @param _user address of the user to check
     * @param _amount the amount to check
     * @return true if the _user can transfer _amount, false otherwise
     **/
    function isTransferAllowed(address _user, uint256 _amount) public view returns (bool) {
        return dataQueryService.getBalanceDecreaseIsAllowed(underlyingAssetAddress, _user, _amount);
    }
}
