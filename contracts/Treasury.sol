// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

import '@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol';
import '@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

contract Treasury is Initializable, OwnableUpgradeSafe {
    using SafeMath for uint256;

    address constant CORE_ADDRESS = 0x62359Ed7505Efc61FF1D56fEF82158CcaffA23D7;
    address private coreLoan;

    modifier onlyCORELoan() {
        require(msg.sender == coreLoan, 'only coreloan can access');
        _;
    }

    function initialize() public initializer {
        OwnableUpgradeSafe.__Ownable_init();
    }

    function setCOREAddress(address _coreLoan) public onlyOwner {
        coreLoan = _coreLoan;
    }

    function transferEthToUser(address payable _user, uint256 _amount) external onlyCORELoan {
        // TODO need to take the ETH out of CORE/ETH LP and transfer to the borrower
        safeTransferEth(_user, _amount);
    }

    function receivePayment(uint256 _principalPayment, uint256 _interestPayment) external payable onlyCORELoan {
        // TODO _principalPayment goes back to CORE/ETH LP
        /**
         * TODO _interestPayment, decides what to do with _interestPayment,
         * buy and burn core ? inject back to LP?
         */
    }

    function transferCOREToUser(address payable _user, uint256 _amount) external onlyCORELoan {
        safeTransfer(CORE_ADDRESS, _user, _amount);
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
