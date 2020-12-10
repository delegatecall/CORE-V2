// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @dev This is CORE lending system services discovery
 */
interface IAddressService {
    function getFacadeAddress() external view returns (address);

    function getTreasuryAddress() external view returns (address);

    function getReserveServiceAddress() external view returns (address);

    function getUserReserveDataServiceAddress() external view returns (address);

    function getDataQueryServiceAddress() external view returns (address);

    function getFeeServiceAddress() external view returns (address);

    function getPriceOracleAddress() external view returns (address);
}
