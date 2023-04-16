// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "./lib/mininterfaces.sol";
import "./Factory.sol";


/// @notice A Cooler is a smart contract escrow that facilitates fixed-duration loans for specific user 
/// and dept-collateral pair

contract Cooler {
    
    // Errors
    error OnlyApproved();
    error Deactivated();
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
    


    /// @notice fill request to the borrower as a lender once This contract is approved on the ClearingHouse Levele
    /// @param reqID index of the requests[]
    /// @param loanId index of the loans[]
    function clear(uint256 reqID) external returns(uint loanId) {
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
        uint256 expiration = block.timestamp + req.duration;

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


    /// @notice Compute interest COST for a given amount, duration, an annulized rate
    /// @param amount of debts tokens
    /// @param rate of interest (annulized)
    /// @param duration of loan in seconds
    /// @return the interest rate of the debts tokens
    function interestFor(uint256 amount, uint256 rate, uint256 duration) public pure returns(uint256) {
        // Compute interest
        uint256 interest = rate * duration / 365 days;
        return amount * interest / decimals;
    }







































    


    // /// @notice cancel a loan request and return collateral
    // /// @param reqID index of request in requests[]
    // function rescind (uint256 reqID) external {
    //     if (msg.sender != owner) 
    //         revert OnlyApproved();

    //     factory.newEvent(reqID, CoolerFactory.Events.Rescind);

    //     Request storage req = requests[reqID];

    //     if (!req.active)
    //         revert Deactivated();
        
    //     req.active = false;
    //     collateral.transfer(owner, collateralFor(req.amount, req.loanToCollateral)); 
    // }



    /// @notice repay a loan to recoup collateral
    /// @param loanID index of loan in loans[]
    /// @param repaid debt tokens to repay
    function repay (uint256 loanID, uint256 repaid) external {
        Loan storage loan = loans[loanID];

        if (block.timestamp > loan.expiry) 
            revert Default();
        
        uint256 decollateralized = loan.collateral * repaid / loan.amount;

        if (repaid == loan.amount) delete loans[loanID];

        else {
            loan.amount -= repaid;
            loan.collateral -= decollateralized;
        }

        debt.transferFrom(msg.sender, loan.lender, repaid);
        collateral.transfer(owner, decollateralized);
    }

    /// @notice roll a loan over
    /// @notice uses terms from request
    /// @param loanID index of loan in loans[]
    function roll (uint256 loanID) external {
        Loan storage loan = loans[loanID];
        Request memory req = loan.request;

        if (block.timestamp > loan.expiry) 
            revert Default();

        if (!loan.rollable)
            revert NotRollable();

        uint256 newCollateral = collateralFor(loan.amount, req.loanToCollateral) - loan.collateral;
        uint256 newDebt = interestFor(loan.amount, req.interest, req.duration);

        loan.amount += newDebt;
        loan.expiry += req.duration;
        loan.collateral += newCollateral;
        
        collateral.transferFrom(msg.sender, address(this), newCollateral);
    }
    

    /// @notice delegate voting power on collateral
    /// @param to address to delegate
    function delegate (address to) external {
        if (msg.sender != owner) 
            revert OnlyApproved();
        IDelegateERC20(address(collateral)).delegate(to);
    }


    // // Lender
    // /// @notice fill a requested loan as a lender
    // /// @param reqID index of request in requests[]
    // /// @param loanID index of loan in loans[]
    // function clear (uint256 reqID) external returns (uint256 loanID) {
    //     Request storage req = requests[reqID];

    //     factory.newEvent(reqID, CoolerFactory.Events.Clear);

    //     if (!req.active) 
    //         revert Deactivated();
    //     else req.active = false;

    //     uint256 interest = interestFor(req.amount, req.interest, req.duration);
    //     uint256 collat = collateralFor(req.amount, req.loanToCollateral);
    //     uint256 expiration = block.timestamp + req.duration;

    //     loanID = loans.length;
    //     loans.push(
    //         Loan(req, req.amount + interest, collat, expiration, true, msg.sender)
    //     );
    //     debt.transferFrom(msg.sender, owner, req.amount);
    // }


    /// @notice change 'rollable' status of loan
    /// @param loanID index of loan in loans[]
    /// @return bool new 'rollable' status
    function toggleRoll(uint256 loanID) external returns (bool) {
        Loan storage loan = loans[loanID];

        if (msg.sender != loan.lender)
            revert OnlyApproved();

        loan.rollable = !loan.rollable;
        return loan.rollable;
    }

    /// @notice send collateral to lender upon default
    /// @param loanID index of loan in loans[]
    /// @return uint256 collateral amount
    function defaulted (uint256 loanID) external returns (uint256) {
        Loan memory loan = loans[loanID];
        delete loans[loanID];

        if (block.timestamp <= loan.expiry) 
            revert NoDefault();

        collateral.transfer(loan.lender, loan.collateral);
        return loan.collateral;
    }

    /// @notice approve transfer of loan ownership to new address
    /// @param to address to approve
    /// @param loanID index of loan in loans[]
    function approve (address to, uint256 loanID) external {
        Loan memory loan = loans[loanID];

        if (msg.sender != loan.lender)
            revert OnlyApproved();

        approvals[loanID] = to;
    }

    /// @notice execute approved transfer of loan ownership
    /// @param loanID index of loan in loans[]
    function transfer (uint256 loanID) external {
        if (msg.sender != approvals[loanID])
            revert OnlyApproved();

        approvals[loanID] = address(0);
        loans[loanID].lender = msg.sender;
    }


    // Views
    
    /// @notice compute collateral needed for loan amount at given loan to collateral ratio
    /// @param amount of collateral tokens
    /// @param loanToCollateral ratio for loan
    function collateralFor(uint256 amount, uint256 loanToCollateral) public pure returns (uint256) {
        return amount * decimals / loanToCollateral;
    }


    // /// @notice compute interest cost on amount for duration at given annualized rate
    // /// @param amount of debt tokens
    // /// @param rate of interest (annualized)
    // /// @param duration of loan in seconds
    // /// @return interest as a number of debt tokens
    // function interestFor(uint256 amount, uint256 rate, uint256 duration) public pure returns (uint256) {
    //     uint256 interest = rate * duration / 365 days;
    //     return amount * interest / decimals;
    // }



    /// @notice check if given loan is in default
    /// @param loanID index of loan in loans[]
    /// @return defaulted status
    function isDefaulted(uint256 loanID) external view returns (bool) {
        return block.timestamp > loans[loanID].expiry;
    }
    
    
    /// @notice check if given request is active
    /// @param reqID index of request in requests[]
    /// @return active status
    function isActive(uint256 reqID) external view returns (bool) {
        return requests[reqID].active;
    }
}
