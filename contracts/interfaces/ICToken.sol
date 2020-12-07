// SPDX-License-Identifier: MIT
// COPYRIGHT cVault.finance TEAM

pragma solidity 0.6.12;

/**
 * @title this is CORE Lending Pool interest bearing wrapping token over native ERC20 token
 * @dev It overrides some key ERC20 methods such as balanceOf(includes occured interest), transfer(check loan to value ration before transfer grante).
 */
interface ICToken {
    /**
     * @dev mints token in the event of users depositing the underlying asset into the lending pool
     * only lending pools can call this function
     * @param _account the address receiving the minted tokens
     * @param _amount the amount of tokens to mint
     */
    function mintOnDeposit(address _account, uint256 _amount) external;

    /**
     * @dev redeem CToken to get the native underlying asset
     * @param _amount the amount being redeemed
     **/
    function redeem(uint256 _amount) external;
}
