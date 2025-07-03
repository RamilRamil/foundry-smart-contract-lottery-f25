// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2PlusMock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2PlusMock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint256) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        return createSubscription(config.vrfCoordinator, config.deployerKey);
    }

    function createSubscription(
        address vrfCoordinator,
        uint256 deployerKey
    ) public returns (uint256) {
        console.log("Creating subscription on ChainID: ", block.chainid);
        vm.startBroadcast(deployerKey);
        uint256 subId = VRFCoordinatorV2PlusMock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();
        console.log("Your sub Id is: ", subId);
        console.log("Please update subscriptionId in HelperConfig!");
        return subId;
    }

    function run() external returns (uint256) {
        return createSubscriptionUsingConfig();
    }
}


contract FundSubscription is Script, CodeConstants {
    uint96 public constant FUND_AMOUNT = 0.01 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        fundSubscription(config.vrfCoordinator, config.subscriptionId, config.linkToken, config.deployerKey);
    }

    function fundSubscription(address vrfCoordinator, uint256 subscriptionId, address link, uint256 deployerKey) public {
        console.log("Funding subscription: ", subscriptionId);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("On ChainID: ", block.chainid);
        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2PlusMock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            // Check balance before attempting transfer
            uint256 balance = LinkToken(link).balanceOf(msg.sender);
            console.log("LINK balance: ", balance);
            if (balance >= FUND_AMOUNT) {
                LinkToken(link).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
                console.log("Subscription funded successfully");
            } else {
                console.log("Insufficient LINK balance, skipping funding");
            }
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script, CodeConstants {
    function addConsumer(address raffle, address vrfCoordinator, uint256 subscriptionId, uint256 deployerKey) public {
        console.log("Adding consumer contract: ", raffle);
        console.log("Using VRFCoordinator: ", vrfCoordinator);
        console.log("On chain id: ", block.chainid);

        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2PlusMock(vrfCoordinator).addConsumer(subscriptionId, raffle);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        addConsumer(raffle, config.vrfCoordinator, config.subscriptionId, config.deployerKey);
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(raffle);
    }
}
