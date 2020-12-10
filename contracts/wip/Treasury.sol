// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';

import '../libraries/WadRayMath.sol';
import '../libraries/EthAddressLib.sol';
import '../libraries/SafeERC20.sol';

import '../interfaces/IAddressService.sol';

contract Treasury is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public facadeAddress;
    IAddressService private AddressService;

    modifier onlyFacade {
        require(facadeAddress == msg.sender, 'The caller must be a lending pool facade contract');
        _;
    }

    function initialize(IAddressService _AddressService) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        AddressService = _AddressService;
        refreshConfigInternal();
    }

    function transferToUser(
        address _reserve,
        address payable _user,
        uint256 _amount
    ) external onlyFacade {
        if (_reserve != EthAddressLib.ethAddress()) {
            IERC20(_reserve).safeTransfer(_user, _amount);
        } else {
            //solium-disable-next-line
            (bool result, ) = _user.call{value: _amount}('');
            require(result, 'Transfer of ETH failed');
        }
    }

    function transferToFeeCollectionAddress(
        address _token,
        address _user,
        uint256 _amount,
        address _destination
    ) external payable onlyFacade {
        address payable feeAddress = address(uint160(_destination)); //cast the address to payable

        if (_token != EthAddressLib.ethAddress()) {
            require(
                msg.value == 0,
                'User is sending ETH along with the ERC20 transfer. Check the value attribute of the transaction'
            );
            IERC20(_token).safeTransferFrom(_user, feeAddress, _amount);
        } else {
            require(msg.value >= _amount, 'The amount and the value sent to deposit do not match');
            //solium-disable-next-line
            (bool result, ) = feeAddress.call{value: _amount}('');
            require(result, 'Transfer of ETH failed');
        }
    }

    function transferToReserve(
        address _reserve,
        address payable _user,
        uint256 _amount
    ) external payable onlyFacade {
        if (_reserve != EthAddressLib.ethAddress()) {
            require(msg.value == 0, 'User is sending ETH along with the ERC20 transfer.');
            IERC20(_reserve).safeTransferFrom(_user, address(this), _amount);
        } else {
            require(msg.value >= _amount, 'The amount and the value sent to deposit do not match');

            if (msg.value > _amount) {
                //send back excess ETH
                uint256 excessAmount = msg.value.sub(_amount);
                //solium-disable-next-line
                (bool result, ) = _user.call{value: excessAmount}('');
                require(result, 'Transfer of ETH failed');
            }
        }
    }

    function refreshConfiguration() external onlyOwner {
        refreshConfigInternal();
    }

    function refreshConfigInternal() internal {
        facadeAddress = AddressService.getFacadeAddress();
    }
}
