// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

interface ILendingPoolAddressesService {
    function getLendingPoolFacadeAddress() external view returns (address);

    function getLendingPoolTreasuryAddress() external view returns (address);
}
