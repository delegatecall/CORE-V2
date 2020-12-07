// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20.sol';

import '../libraries/WadRayMath.sol';

import '../interfaces/ICToken.sol';
import '../interfaces/ILendingPoolAddressService.sol';
import '../interfaces/ILendingPoolReserveService.sol';
import '../interfaces/ILendingPoolFacade.sol';

/**
 * @title CORE interest bearing liquidty pool ERC20
 */

contract CToken is ICToken, ERC20UpgradeSafe, OwnableUpgradeSafe {
    using WadRayMath for uint256;

    uint256 public constant UINT_MAX_VALUE = uint256(-1);

    event MintOnDeposit(address indexed _from, uint256 _value, uint256 _fromBalanceIncrease, uint256 _fromIndex);

    address public underlyingAssetAddress;

    mapping(address => uint256) private userIndexes;
    ILendingPoolAddressService private addressService;
    ILendingPoolReserveService private reserveService;
    ILendingPoolFacade private poolFacade;

    modifier onlyLendingPool {
        require(msg.sender == address(poolFacade), 'The caller of this function must be a lending pool');
        _;
    }

    function initialize(
        ILendingPoolAddressService _addressService,
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

    /**
     * @dev mints token in the event of users depositing the underlying asset into the lending pool
     * only lending pools can call this function
     * @param _account the address receiving the minted tokens
     * @param _amount the amount of tokens to mint
     */
    function mintOnDeposit(address _account, uint256 _amount) external override onlyLendingPool {
        //cumulates the balance of the user
        (, , uint256 balanceIncrease, uint256 index) = cumulateBalanceInternal(_account);

        //mint an equivalent amount of tokens to cover the new deposit
        _mint(_account, _amount);

        emit MintOnDeposit(_account, _amount, balanceIncrease, index);
    }

    function refreshConfigInternal() internal {
        poolFacade = ILendingPoolFacade(addressService.getLendingPoolFacadeAddress());
        reserveService = ILendingPoolReserveService(addressService.getLendingPoolReserveServiceAddress());
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
}
