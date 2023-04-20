// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "../lib/mininterfaces.sol";
import "./TestFactory.sol";


/// @notice A Cooler is a smart contract escrow that facilitates fixed-duration loans for specific user 
/// and dept-collateral pair

contract Cooler {
    
    // Errors
    error OnlyApproved();
    error Deactivated();
    error OnlyLender();
    error Default();
    error NoDefault();
    error NotRollable();

    // Data structures
    Request[] public requests;

    // A loan begins with a borrower create a borrow request, it specifies:
    struct Request {
        // The amount they want to borrow;
        uint256 amount; 
        // The annualized percentage they will pay as interest
        uint256 interest;
        // The loan to collateral ratio thet want
        // the amount of assets they are willing to put as collateral to borrow the money(borrow 10k to 20k as collateral)
        // In this case loan to collateral is 50%
        uint256 loanToCollateral;
        // The lengh of time until the loan defaults
        uint256 duration;
        // Any lender can clear an active loan request
        bool active;
    }


    Loan[] public loans;

    // A request is converted to loan, once the lender clears it
    struct Loan {
        Request request;
        // The amount of debt owed
        uint256 amount;
        // The amount of collaterak pledged
        uint256 collateral;
        // the time when the loan defaults
        uint256 expiry;
        // Whether the loan can be rolled over
        bool rollable;
        // The lender's address
        address lender;
    }

    // Facilitates transfer of lender ownership to new address
    mapping(uint256 => address) public approvals;

    /************* Immutables ************************/

    // owns the address in this escrow 
    address public immutable owner;

    // Lent token
    ERC20 public immutable debt;

    // The token is borrowerd against
    ERC20 public immutable collateral;

    // This contract created the Cooler;
    CoolerFactory public immutable factory;

    // Decimals
    uint256 private constant decimals = 1e18;


    /************* Initialization ************************/
     constructor(address _owner, ERC20 _collateral, ERC20 _debt) {
            owner = _owner;
            collateral = _collateral;
            debt = _debt;
            factory = CoolerFactory(msg.sender);
    }


    /// @notice request a loan with given parameters
    /// @notice collateral is taken at time of request
    /// @param _amount of debt tokens to borrow
    /// @param _interest to pay(annulized % of "amount")
    /// @param _loanToCollateral debt tokens per collateral tokens pledged
    /// @param _duration of loan tenure in seconds
    /// @param reqId index of request in requests[]
    function request(
        uint256 _amount,
        uint256 _interest,
        uint256 _loanToCollateral,
        uint256 _duration
    ) external returns (uint256 reqId) {
        // Get the reqId by getting the first element at requests array which is 0
        reqId = requests.length;

        // Push the loanRequest to the requests array
        requests.push(
            Request(_amount, _interest, _loanToCollateral, _duration, true)
        );

        // Transfer user's collateral to this contract
        collateral.transferFrom(msg.sender, address(this), collateralFor(_amount, _loanToCollateral));
        
        // Emit an Event
        factory.newEvent(reqId, CoolerFactory.Events.Request);

    }



    /// @notice cancel a loan request and return collateral
    /// @param reqID index of request in requests[]
    function rescind(uint256 reqID) external {
        // Check if the caller is the owner
        if(msg.sender != owner) {
            revert OnlyApproved();
        }

        factory.newEvent(reqID, CoolerFactory.Events.Rescind);

        Request storage req = requests[reqID];

        // Check if the the request is in active state or not(true/false)
        if(!req.active) {
            revert Deactivated();
        }

        req.active = false;
        // Transer Collateral to the borrower
        collateral.transfer(owner, collateralFor(req.amount, req.loanToCollateral));

    }


    /// @notice Reapay part of the loan or the total amount of the loan
    /// @param loanId index of the loans[]
    /// @param repaid amount of repaid loan
    function repay(uint256 loanId, uint256 repaid, uint256 time) external {
        // Get the loan data from the storage based on the loanId
        Loan storage loan = loans[loanId];
        
        // Check if the loan is not expired
        if(time > loan.expiry) {
            revert Default();
        }

        // Compute the amount of collateral to send to the borrower based on repaid amount
        uint256 decollateralized = loan.collateral * repaid / loan.amount;

        if( repaid == loan.amount) delete loans[loanId];
        
        else {
            loan.amount -= repaid;
            loan.collateral -= decollateralized;
        }
        
        // Send the repaid amount to the lender
        debt.transferFrom(msg.sender, loan.lender, repaid);
        collateral.transfer(owner, decollateralized);

    }

    

    /// @notice Roll a loan over
    /// @param loanId amount of repaid loan
    function roll(uint256 loanId, uint256 time) external {

        Loan storage loan = loans[loanId];
        Request memory req = requests[loanId];

        // Check if the loan is not expiry
        if(time > loan.expiry)
            revert Default();

        // Check if the loan is rollable or not
        if(!loan.rollable) {
            revert NotRollable();
        }

        // Compute newCool & newInterest
        uint256 newColl = collateralFor(loan.amount, req.loanToCollateral) - loan.collateral; // 2oGHM - 1oGMH
        uint256 newInterest = interestFor(loan.amount, req.interest, req.duration);
        
        loan.amount += newInterest;
        loan.collateral += newColl;
        loan.expiry += req.duration;

        collateral.transferFrom(msg.sender, address(this), newColl);

    }
    
    /// @notice fill request to the borrower as a lender once this contract is approved on the ClearingHouse Level
    /// @param reqID index of the requests[]
    /// @param loanId index of the loans[]
    function clear(uint256 reqID, uint256 time) external returns(uint loanId) {
        // Retrieve the req for a specific reqID
        Request storage req = requests[reqID];

        // Check if the req that lender wants to clear is active(true) if it's not, then we set it to false.
        if(!req.active) {
            revert Deactivated();
        }
        
        req.active = false;

        // compute Interest rate for a given amount
        uint256 interest = interestFor(req.amount, req.interest, req.duration);
        // compute Collateral
        uint256 collat = collateralFor(req.amount, req.loanToCollateral);
        uint256 expiration = time + req.duration;
        
        // Get loanId
        loanId = loans.length;
        loans.push(
            Loan(req, req.amount + interest, collat, expiration, true , msg.sender)
        );
        
        // Transfer the Debt tokens to the borrower
        debt.transferFrom(msg.sender, owner, req.amount);

        // Emit Event
        factory.newEvent(reqID, CoolerFactory.Events.Clear);
    }

    /// @notice set rollable option to false
    /// @param loanId loanId of the loan
    function toggleRoll(uint256 loanId) external returns(bool) {
        Loan storage loan = loans[loanId];

        if(msg.sender != loan.lender) {
            revert OnlyLender();
        }
        loan.rollable = !loan.rollable;
        return loan.rollable;

    }

    /// @notice Defaulted function to send the collateral to the lender
    /// @param loanId index of the loans[]
    function defaulted(uint256 loanId, uint256 time) external returns(uint256) {
        Loan memory loan = loans[loanId];
        delete loans[loanId];

        // Check if the the loan is defaulted
        if(time <= loan.expiry) 
            revert NoDefault();

        // Transfer collateral to the lender;
        collateral.transfer(loan.lender, loan.collateral);
        return loan.collateral;
    }

    // Views
    
    /// @notice compute collateral needed for loan amount at given loan to collateral ratio
    /// @param amount of collateral tokens
    /// @param loanToCollateral ratio for loan
    function collateralFor(uint256 amount, uint256 loanToCollateral) public pure returns (uint256) {
        return amount * decimals / loanToCollateral;
    }

    /// @notice compute interest cost on amount for duration at given annualized rate
    /// @param amount of debt tokens
    /// @param rate of interest (annualized)
    /// @param duration of loan in seconds
    /// @return interest as a number of debt tokens
    function interestFor(uint256 amount, uint256 rate, uint256 duration) public pure returns (uint256) {
        uint256 interest = rate * duration / 365 days;
        return amount * interest / decimals;
    }

}
