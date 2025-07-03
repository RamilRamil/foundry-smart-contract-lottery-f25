// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2, stdError} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {LinkToken} from "../mocks/LinkToken.sol";
import {VRFCoordinatorV2PlusMock} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2PlusMock.sol";
import {Vm} from "forge-std/Vm.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 public entranceFee;
    uint256 public interval;
    address public vrfCoordinator;
    bytes32 public gasLane;
    uint256 public subscriptionId;
    uint32 public callbackGasLimit;
    address public linkToken;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant LINK_STARTING_BALANCE = 100 ether;

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleUpkeepNeeded(bool upkeepNeeded, bytes);

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.deployRaffle();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();
        entranceFee = networkConfig.entranceFee;
        interval = networkConfig.interval;
        vrfCoordinator = networkConfig.vrfCoordinator;
        gasLane = networkConfig.gasLane;
        subscriptionId = networkConfig.subscriptionId;
        callbackGasLimit = networkConfig.callbackGasLimit;
        linkToken = networkConfig.linkToken;
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        if (block.chainid == LOCAL_CHAIN_ID) {
            // Получаем subscription ID, который использует контракт raffle
            vm.startPrank(msg.sender);
            // Получаем подписку, созданную в DeployRaffle и дополнительно финансируем её
            uint256 raffleSubscriptionId = raffle.getSubscriptionId();
            console2.log("Raffle subscription ID:", raffleSubscriptionId);
            VRFCoordinatorV2PlusMock(vrfCoordinator).fundSubscriptionWithNative{value: 10 ether}(raffleSubscriptionId);
            vm.stopPrank();
        }
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(abi.encodeWithSignature("Raffle__NotEnoughEthSent()"));
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        address expectedPlayer = PLAYER;
        address player = raffle.getPlayers(0);

        assertEq(player, expectedPlayer);
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    modifier raffleIsEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public raffleIsEnteredAndTimePassed{
        raffle.performUpkeep("");

        vm.prank(PLAYER);
        vm.expectRevert(abi.encodeWithSignature("Raffle__RaffleNotOpen()"));
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertEq(upkeepNeeded, false);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen() public raffleIsEnteredAndTimePassed{
        raffle.performUpkeep("");
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assertEq(upkeepNeeded, false);
    }

    /*//////////////////////////////////////////////////////////////
                            performUpkeep
    //////////////////////////////////////////////////////////////*/

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleIsEnteredAndTimePassed{
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, uint256(rState)));
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleIsEnteredAndTimePassed{
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == uint256(Raffle.RaffleState.CALCULATING));
    }

    /*//////////////////////////////////////////////////////////////
                            fulfillRandomWords
    //////////////////////////////////////////////////////////////*/

    modifier skipFork() {
        if (block.chainid != 31337){
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 requestId) public raffleIsEnteredAndTimePassed skipFork{
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2PlusMock(vrfCoordinator).fulfillRandomWords(requestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerAndSendsMoneyToWinner() public raffleIsEnteredAndTimePassed skipFork{
        // Arrange
        uint256 additionalPlayers = 3; 
        uint256 startingIndex = 1;
        address expectedWinner = address(uint160(startingIndex + 100)); // Используем адрес 101 вместо 1

        for (uint256 i = startingIndex; i < startingIndex + additionalPlayers; i++) {
            address player = address(uint160(i + 100)); // Используем адреса 101, 102, 103 вместо 1, 2, 3
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalPlayers + 1);
        uint256 winnerStartingBalance = expectedWinner.balance;
        
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Pretend to be chainlink VRF to get random number & pick winner
        VRFCoordinatorV2PlusMock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId), 
            address(raffle)
        );
        
        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState rState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;

        assert(uint256(rState) == uint256(Raffle.RaffleState.OPEN));
        assert(expectedWinner == recentWinner);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(address(raffle).balance == 0);
    }
}