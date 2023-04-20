// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";
import "./MockTreasury.sol";
import "./TestCH.sol";

contract ContractTest is Test {
    ERC20 private gOHM;
    ERC20 private dai;

    address borrower = address(0x1);
    // address lender = address(0x2);

    // Import all the 
    Treasury private treasury;
    CoolerFactory private factory;
    Cooler private cooler;
    ClearingHouse private clearingHouse;

    uint duration = 365 days;
    uint interest = 2e16; // This represent (0.02 Ether) which is 2e16 in Wei
    uint loanToCollateral = 25e20; // 25% per 365 days

    uint time = 100_000;

    uint256[] budget = [2e24, 2e24, 2e24];

    function setUp() public {

        treasury = new Treasury();
        gOHM = new ERC20("gOHM", "gOHM");
        dai = new ERC20("DAI", "DAI");

        vm.label(address(borrower), "Borrower");
        vm.label(address(treasury), "Treasury Contract");
        vm.label(address(gOHM), "gOHM Token");
        vm.label(address(dai), "Dai Token");
        vm.label(address(factory), "Cooler Factory Contract");
        vm.label(address(clearingHouse), "Clearing House Contract");
        vm.label(address(cooler), "Cooler Contract");
        vm.label(address(this), "This contract");

        factory = new CoolerFactory();
        clearingHouse = new ClearingHouse(address(this), address(this), gOHM, dai, factory, address(treasury), budget); 

        uint mintAmount = 6e24;  // Funds the trasury with 2 million
        
        dai.mint(address(treasury), mintAmount);
        clearingHouse.fund(mintAmount);
        
        // Create a pool gOHM as collateral and dai to borrow
        cooler = Cooler(factory.generate(gOHM, dai));
        console2.log("Cooler address",address(cooler));

        // Mint to alice 2 millions tokens
        gOHM.mint(borrower,mintAmount);
        gOHM.mint(address(this), mintAmount);
        dai.mint(address(this), mintAmount);
    }


    function testRequest() public returns(uint reqID) {
        uint collateral = 1e18; // one gOHM token
        uint amount = collateral * loanToCollateral / 1e18; // Equalivalent of 

        // Approve the cooler contract to spend my collateral
        gOHM.approve(address(cooler), collateral);

        // Create a loan request
        reqID = cooler.request(amount, interest, loanToCollateral, duration);
        console2.log("Returned reqID", reqID);

        uint coolerBalanceBefore = gOHM.balanceOf(address(cooler));
        uint coolerBalanceAfter = gOHM.balanceOf(address(cooler)) + collateral;

        uint BalanceBeforeThis = gOHM.balanceOf(address(this));
        console2.log("Cooler balance before Request", coolerBalanceBefore);
        console2.log("This contract balance afyer requests", BalanceBeforeThis);
        // Expect collateral to be transsfered
        assertEq(coolerBalanceAfter, 2000000000000000000);
        console2.log("Cooler balance after request", coolerBalanceBefore + collateral);
    }


    function testRescind() public {
        uint256 balance0 = gOHM.balanceOf((address(this))); 
        uint coolerBalanceBefore = gOHM.balanceOf(address(cooler));
        uint256 reqID = testRequest();

        // Get the active value from requests[reqID] using destructing
        (uint256 amount,,uint256 ltc,, bool active) = cooler.requests(reqID);

        console2.log("The status of active value before loan rescind", active);
        console2.log("This address balance in gOHM", balance0);
        console2.log("Cooler balance in gOHM", coolerBalanceBefore);

        // Check if the loan is active
        assertTrue(active);

        // Rescind the loan
        cooler.rescind(reqID);

        (amount,,ltc,, active) = cooler.requests(reqID);

        console2.log("The status of active value after rescind", active);

        assertTrue(!active);
    }


    function testClear() public returns (uint256 loanId) {
        setUp();

        uint256 reqID = testRequest();
        loanId = clearingHouse.clear(cooler, reqID, time);
    }



    function testRepay() public {
        uint loanId = testClear();

        // Get the balance of the lender(clearingHouse) and borrower before
        uint256 balancegOHMbefore = gOHM.balanceOf(address(address(this))); // 5999999000000000000000000
        uint256 balanceDaiBefore = dai.balanceOf(address(clearingHouse)); // 1997500000000000000000000 


        (,uint amount, uint256 collateral, ,,) = cooler.loans(loanId);
        uint256 repaidAmount50 = amount * 50 / 100;
        uint256 collateral50 = collateral * 50 / 100;

        // Address(this) should approve dai transfer because (this) interact with cool contract to repay the loan
        dai.approve(address(cooler), repaidAmount50); 
        cooler.repay(loanId, repaidAmount50, time);

        // Get the balance of the lender(clearingHouse) and borrower after
        uint256 balancegOHMAfter = gOHM.balanceOf(address(address(this))); // Collateral
        uint256 balanceDaiAfter = dai.balanceOf(address(clearingHouse)); // Debt tokens
        // Expect that collateral has been returned
        assertEq(balancegOHMAfter, balancegOHMbefore + collateral50);
        assertEq(balanceDaiAfter, balanceDaiBefore + repaidAmount50);   
    }


    function testRoll() public {
        // setUp();
        // testRequest();
        /**
            When Roll is called, we have to check the 3 states
            1- If the cooler contract's balance for gGHM incresead for specific loanID
            2- If the new Interest amount has been increased by the newInterest
            3- The expiry duration has incresed
        */

        uint256 loanId = testClear();

        uint256 collateralbeforeBal = gOHM.balanceOf(address(cooler));

        (,uint256 loan0, uint256 collateral0 , uint256 expiry0,,) = cooler.loans(loanId);
        
        // newColl to transfer to the cooler contract, CollateralFor 
        uint256 newColl = collateral0 * interest / 1e18;

        // Compute the new interest to add to the existing amount, interestFor
        uint256 newInerest = loan0 * interest / 1e18;

        // Allow cooler function to transfer collateral from my wallet
        gOHM.approve(address(cooler), newColl);
        cooler.roll(loanId, time);

        (,uint256 loan1, uint256 collateral1, uint256 expiry1,,) = cooler.loans(loanId);

        uint256 collateralAfterBal = gOHM.balanceOf(address(cooler));

        assertEq(loan1, loan0 + newInerest);
        assertEq(collateral1, collateral0 + newColl);
        assertEq(expiry1, expiry0 + duration);

        // Make sure that the balance of cooler contract increased
        assertEq(collateralAfterBal, collateralbeforeBal + newColl);
    }


    function testToggleRoll() public {
        testClear();

        uint256 loanId = testClear();

        (,,,,bool rollable, address lender) = cooler.loans(loanId);
        assertTrue(rollable);

        vm.startPrank(address(lender));
        cooler.toggleRoll(loanId);
        vm.stopPrank();

        (,,,,rollable,) = cooler.loans(loanId);
        assertTrue(!rollable);
    }


    function testDefaulted() public {
         testClear();

        uint256 loanId = testClear();

        (,,uint256 collateral, uint256 expiry,, address lender0) = cooler.loans(loanId);
        
        uint256 lenderBalanceBef = gOHM.balanceOf(lender0);
        console2.log("balance of lender", lenderBalanceBef);

        vm.startPrank(address(lender0));
        cooler.defaulted(loanId, expiry + 100);
        vm.stopPrank();
        
        uint256 lenderBalanceAfter = gOHM.balanceOf(lender0);
        assertEq(lenderBalanceAfter, collateral + lenderBalanceBef);
    }  

}

