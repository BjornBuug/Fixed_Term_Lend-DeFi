// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Factory.sol";
import "../lib/mininterfaces.sol";


contract ClearingHouse {
    // Errors
    error OnlyApproved();
    error OnlyFromFactory();
    error BadEscrow();
    error InterestMinimum();
    error LTCMaximum();
    error DurationMaximum();

    // Roles
    address public operator;
    address public overseer;
    address public pendingOperator;
    address public pendingOverseer;

    // Relevant Contracts
    ERC20 public immutable dai;
    ERC20 public immutable gOHM;
    CoolerFactory public immutable factory;
    address public immutable treasury;

    // Parameter Bounds
    uint256 public constant minimumInterest = 2e16; // 2%
    uint256 public constant maxLTC = 2_500 * 1e18; // 2,500
    uint256 public constant maxDuration = 365 days; // 1 year

    constructor(
        address oper,
        address over,
        ERC20 g,
        ERC20 d,
        CoolerFactory f,
        address t
    ) {

        operator = oper;
        overseer = over;
        gOHM = g;
        dai = d;
        factory = f;
        treasury = t;
    }

    
    /// @notice clear a requesting loan
    /// @param cooler contract requesting loan 
    /// @param reqId loan id in escrow contract
    /// @return reqId return the id of the cleared loan
    function clear(Cooler cooler, uint256 reqId) external returns(uint256) {
        
        // check if the caller is the operator/lender
        if(msg.sender != operator)
            revert OnlyApproved();

        // Check if the cooler address/borrower was created from the Factory
        if(!factory.created(address(cooler))) 
            revert OnlyFromFactory();
    
        // Check if the lending is clearing the right pool oGMH / dai
        if(cooler.collateral() != gOHM || cooler.debt() != dai)
            revert BadEscrow();

        // Validate if the term of the borrowing request is within valid conditions
        (uint256 amount,
         uint256 interest,
         uint256 ltc,
         uint256 duration,) = cooler.requests(reqId);

        if(interest < minimumInterest) {
            revert InterestMinimum();
        }
        if(ltc > maxLTC) {
            revert LTCMaximum();
        }
        if(duration > maxDuration) {
            revert DurationMaximum();
        }

        // Operator Approves the cooler contract to spend dai
        dai.approve(address(cooler), amount); 
        return cooler.clear(reqId);
    }


    /// @notice Allow the lender to toggle a loan
    /// @param cooler contract 
    /// @param loanId loan id in escrow contract
    function toggleRoll(Cooler cooler, uint256 loanId) external {
        if(msg.sender != operator) {
            revert OnlyApproved();
        }

        cooler.toggleRoll(loanId);
    }


    // Oversight

    /// @notice pull funding from treasury
    function fund (uint256 amount) external {
        if (msg.sender != overseer) 
            revert OnlyApproved();
        ITreasury(treasury).manage(address(dai), amount);
    }

    /// @notice return funds to treasury
    /// @param token to transfer
    /// @param amount to transfer
    function defund (ERC20 token, uint256 amount) external {
        if (msg.sender != operator && msg.sender != overseer) 
            revert OnlyApproved();
        token.transfer(treasury, amount);
    }



} 
