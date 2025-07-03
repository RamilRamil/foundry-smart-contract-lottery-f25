// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployRaffle is Script {

    function deployRaffle() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        if (networkConfig.subscriptionId == 0) {
            CreateSubscription createSub = new CreateSubscription();
            uint256 subId = createSub.createSubscription(networkConfig.vrfCoordinator, networkConfig.deployerKey);
            
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(networkConfig.vrfCoordinator, subId, networkConfig.linkToken, networkConfig.deployerKey);

            vm.startBroadcast(networkConfig.deployerKey);
            Raffle raffle = new Raffle(
                networkConfig.entranceFee,
                networkConfig.interval,
                networkConfig.vrfCoordinator,
                networkConfig.gasLane,
                subId,
                networkConfig.callbackGasLimit
            );
            vm.stopBroadcast();

            AddConsumer addConsumer = new AddConsumer();
            addConsumer.addConsumer(address(raffle), networkConfig.vrfCoordinator, subId, networkConfig.deployerKey);

            return (raffle, helperConfig);
        }

        vm.startBroadcast(networkConfig.deployerKey);
        Raffle raffle = new Raffle(
            networkConfig.entranceFee,
            networkConfig.interval,
            networkConfig.vrfCoordinator,
            networkConfig.gasLane,
            networkConfig.subscriptionId,
            networkConfig.callbackGasLimit
        );
        vm.stopBroadcast();

        return (raffle, helperConfig);
    }
    
    function run() public {
        deployRaffle();
    }
}