// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TestCooler.sol";


// @notice the Cooler Factory creates new Cooler escrow contracts
contract CoolerFactory { 
    // A gloabl event when a loan request is created
    event Request(address cooler, address collateral, address debt, uint256 reqID);
    
    // A global event when a loan request is rescinded
    event Rescind (address cooler, uint256 reqID);

    // A global event when a loan request is cleared
    event Clear(address cooler, uint256 reqID);

    // Mapping to validate deployed coolers
    mapping(address => bool) public created;

    // Mapping to prevent duplicate coolers
    mapping(address => mapping(ERC20 => mapping(ERC20 => address))) private coolerFor;
    
    // Mapping to query Coolers for Collateral-Dept pair
    mapping(ERC20 => mapping(ERC20 => address[])) public coolersFor;

    enum Events {
        Request, 
        Rescind,
        Clear
    }

    /// @notice creates a new Escrow contract for collateral and debt tokens
    function generate(ERC20 collateral, ERC20 debt) external returns(address cooler) {
        // return address if cooler exists
        cooler = coolerFor[msg.sender][collateral][debt];
        
        // else
        if(cooler == address(0)) {
            // Create an instance of Cooler escrow contracts
            cooler = address(new Cooler(msg.sender, collateral, debt));
            coolerFor[msg.sender][collateral][debt] = cooler;
            coolersFor[collateral][debt].push(cooler);
            created[cooler] = true;
        }

    }
    

    /// @notice emit an event each time a request is interected with with on a Cooler contracts
    /// @dev The goal is the create a function that can handle emit an event based on certains condtions
    function newEvent(uint256 id, Events ev) external {
        // Check if the cooler is created or not
        require(created[msg.sender], "The cooler is not created");
        if(ev == Events.Request) {
            emit Request(msg.sender, 
                        address(Cooler(msg.sender).collateral()), // msg.sender is the Factory contracts
                        address(Cooler(msg.sender).debt()),
                        id
                        );
        } else if(ev == Events.Rescind) {
            emit Rescind(msg.sender, id);
        }
          else {
            emit Clear(msg.sender, id);
        }
    }

}
