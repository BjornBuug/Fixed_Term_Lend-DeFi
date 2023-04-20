## How does the protocol works
    borrower can create different loans request for fix-duration with fixed-interest, etc. Lenders can clear 
    a borrower request for loan.
    1- Borrower will create a Cooler/Pool for their desired collateral that they want to deposit and debt that they would like to take DAI/USDT token with the generate() function at the CoolerFactory
    2- The borrower will create a loan Request specifies the loan terms that the borrower is looking for...
    2.a - A borrower can rescind their request at any time before it has been cleared.
    3- Loan is created when a lender clears/fulfill a loan request. Debt tokens are transfer from the lender to the borrower
    and the borrowers collateral is locked in the Cooler until the loan has been Repaid
    

    # Cooler + Factory = Cooler Loans
    
