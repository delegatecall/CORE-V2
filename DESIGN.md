# CORE Bottom Price Lending Pool Design

This architecture is heavily inspired by AAVE protocol[https://aave.com/]. Moving from peer to peer loan matching design to reserves based solution.

## Pool Design

At the PoC stage, the lending pool includes only two reserves:

1. core token reserve, which is used as collateral only. Borrower need to deposit CORE token first before they can take loan
   
2. Eth Reserve, which is used as lending only. Eth in this reserve is mainly from CORE/ETH Uni LP. Hope it will attract eth from wider group
   
Interest Rate:

It is essential risk free to borrow against CORE bottom price. Depending on the demand, a variable interest rate between 5% to 15% is reasonable. It may increase LP provider's APY by 1% to 2%? 


Interest Rate is calculated based on the available eth






