// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;
import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/ILendingPoolAddressesService.sol';

contract LendingPoolAddressesService is ILendingPoolAddressesService, Ownable {
    address private lendingPoolFacadeAddress;
    address private lendingPoolTreasuryAddress;

    function getLendingPoolFacadeAddress() public override view returns (address) {
        return lendingPoolFacadeAddress;
    }

    function setLendingPoolFacadeAddress(address _new) public onlyOwner {
        lendingPoolFacadeAddress = _new;
    }

    function getLendingPoolTreasuryAddress() public override view returns (address) {
        return lendingPoolTreasuryAddress;
    }

    function setLendingPoolTreasuryAddress(address _new) public onlyOwner {
        lendingPoolTreasuryAddress = _new;
    }
}
