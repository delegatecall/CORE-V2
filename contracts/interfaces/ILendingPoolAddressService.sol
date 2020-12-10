// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @dev This is CORE lending system services discovery
 */
interface ILendingPoolAddressService {
    function getLendingPoolFacadeAddress() external view returns (address);

    function getLendingPoolTreasuryAddress() external view returns (address);

    function getLendingPoolReserveServiceAddress() external view returns (address);

    function getLendingPoolUserReserveDataServiceAddress() external view returns (address);

    function getLendingPoolDataQueryServiceAddress() external view returns (address);

    function getLendingPoolFeeServiceAddress() external view returns (address);

    function getPriceOracleAddress() external view returns (address);
}
