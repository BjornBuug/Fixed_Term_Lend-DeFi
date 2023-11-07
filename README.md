## How does the protocol work?
The borrower can create different loan requests for a fixed duration with fixed interest rates, among other options. Lenders can then review and clear a borrower's request for a loan.

Here are the steps involved:

1- The borrower creates a Pool for their desired collateral that they want to deposit, along with the debt they would like to take in DAI/USDT tokens. This can be done using the generate() function at the CoolerFactory.

2- The borrower then creates a loan request that specifies the loan terms they are looking for.

3- The borrower can rescind their request at any time before it has been cleared.

4- When a lender clears/fulfills a loan request, a loan is created, and the debt tokens are transferred from the lender to the borrower. The borrower's collateral is locked in the Cooler until the loan has been repaid.

5- If the lender allows it, the borrower can change the loan terms.

6- If the borrower fails to repay the loan on time, the escrow contract (Cooler) will send the held collateral to the lender. The borrower can keep the borrowed amount.
