// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @title this is CORE Lending Pool interest bearing wrapper over native ERC20 token
 */
interface ICToken {
    /**
     * @dev mints token in the event of users depositing the underlying asset into the lending pool
     * only lending pools can call this function
     * @param _account the address receiving the minted tokens
     * @param _amount the amount of tokens to mint
     */
    function mintOnDeposit(address _account, uint256 _amount) external;
}
