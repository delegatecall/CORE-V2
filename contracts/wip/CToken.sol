// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import '../libraries/ERC20.sol';
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

    function calculateCumulatedBalanceInternal(address _user, uint256 _balance) internal view returns (uint256) {
        return
            _balance
                .wadToRay()
                .rayMul(reserveService.getReserveNormalizedIncome(underlyingAssetAddress))
                .rayDiv(userIndexes[_user])
                .rayToWad();
    }
}
