// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2PlusMock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2PlusMock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    uint256 public constant MOCK_BASE_FEE = 0.1 ether;
    uint256 public constant MOCK_GAS_PRICE = 1e6;
    uint256 public constant MOCK_WEI_PER_UNIT_LINK = 1e6;
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is Script, CodeConstants {

    error HelperConfig__NetworkNotSupported();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address linkToken;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaNetworkConfig();
        networkConfigs[LOCAL_CHAIN_ID] = getOrCreateAnvilEthConfig();
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator == address(0)) {
            getOrCreateAnvilEthConfig();
        } else if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else {
            revert HelperConfig__NetworkNotSupported();
        }
    }

    function getConfig() public returns(NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if(activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        VRFCoordinatorV2PlusMock vrfCoordinatorV2_5Mock = new VRFCoordinatorV2PlusMock(
            uint96(MOCK_BASE_FEE),
            uint96(MOCK_GAS_PRICE)
        );

        LinkToken link = new LinkToken();

        vm.stopBroadcast();


        return NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30, // 30 seconds
            vrfCoordinator: address(vrfCoordinatorV2_5Mock),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 0, // If left as 0, our scripts will create one!
            callbackGasLimit: 500000, // 500,000 gas
            linkToken: address(link),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

    function getSepoliaNetworkConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30,
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 0, // This will be set when we create a subscription
            callbackGasLimit: 500000,
            linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }
}