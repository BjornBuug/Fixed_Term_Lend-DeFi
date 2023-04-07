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
    address lender = address(0x2);

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
        vm.label(address(lender), "Lender");

        factory = new CoolerFactory();
        clearingHouse = new ClearingHouse(address(this), address(this), gOHM, dai, factory, address(treasury), budget); 

        uint mintAmount = 6e24;  // Funds the trasury with 2 million
        // dai.mint(address(treasury), mintAmount);

        // clearingHouse.fund(mintAmount);
        
        // Create a pool gOHM as collateral and dai to borrow
        cooler = Cooler(factory.generate(gOHM, dai));

        // Mint to alice 2 millions tokens
        gOHM.mint(borrower,mintAmount);
        gOHM.mint(address(this), mintAmount);

    }

    function testRequest() public returns(uint reqID) {
        uint collateral = 1e18; // one gOHM token
        uint amount = collateral * loanToCollateral / 1e18;

        vm.startPrank(borrower);
        // Approve the cooler contract to spend my collateral
        gOHM.approve(address(cooler), collateral);

        // Create a loan request
        reqID = cooler.request(amount, interest, loanToCollateral, duration);
        vm.stopPrank();

        uint coolerBalanceBefore = gOHM.balanceOf(address(cooler));
        uint coolerBalanceAfter = gOHM.balanceOf(address(cooler)) + collateral;

        console2.log("Cooler contract before", coolerBalanceBefore);

        // Expect collateral to be transsfered
        assertEq(coolerBalanceAfter, 2000000000000000000);
        console2.log("Cooler contract after", coolerBalanceBefore + collateral);
    }




}

