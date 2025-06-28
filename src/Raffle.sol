// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract

// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private

// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

// Errors
error Raffle__NotEnoughEthSent();
error Raffle__RaffleNotOpen();
error Raffle__TransferFailed();

/**
 * @title A simple raffle contract
 * @author Ramil Mustafin
 * @notice This contract is a simple raffle contract that allows users to enter a raffle and win a prize.
 * @dev This contract uses Chainlink VRF to randomly select a winner.
 */
contract Raffle is VRFConsumerBaseV2 {

    // Enums
    enum RaffleState {
        OPEN,
        CALCULATING,
        CLOSED
    }

    // State variables
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint32 private immutable i_callbackGasLimit;
    bytes32 private immutable i_keyHash;
    uint64 private immutable i_subscriptionId;
    VRFCoordinatorV2Interface immutable i_vrfCoordinator;     
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    address payable[] private s_players;
    RaffleState private s_raffleState;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;

    // Events
    event RaffleEnter(address indexed player);
    event RafflePickWinner(address indexed winner);

    constructor(uint256 entranceFee, uint256 interval, address vrfCoordinator, bytes32 gasLane, 
                uint64 subscriptionId, uint32 callbackGasLimit) 
    VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRuffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    function pickWinner() external {
        s_raffleState = RaffleState.CALCULATING;

        if(block.timestamp - s_lastTimeStamp > i_interval) {
            revert Raffle__RaffleNotOpen();
        }

        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: uint64(i_subscriptionId),
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({
                nativePayment: false
            }))
        });

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            request.keyHash,
            uint64(request.subId),
            uint16(request.requestConfirmations),
            uint32(request.callbackGasLimit),
            uint32(request.numWords)
        );
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        s_raffleState = RaffleState.CLOSED;
        s_lastTimeStamp = block.timestamp;
        emit RafflePickWinner(winner);
    }

    // Getters
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }
}
