// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

interface ILendingPoolAddressService {
    function getLendingPoolFacadeAddress() external view returns (address);

    function getLendingPoolTreasuryAddress() external view returns (address);

    function getLendingPoolReserveServiceAddress() external view returns (address);

    function getLendingPoolUserLoanDataServiceAddress() external view returns (address);

    function getLendingPoolDataQueryServiceAddress() external view returns (address);
}
