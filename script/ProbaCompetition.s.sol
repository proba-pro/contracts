// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/ProbaCompetitionFactory.sol";

contract DeployGoerliProbaFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ETH_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Goerli setup for VRF v2
        address protocolAddress = address(0x0E5315780d39ce7AA64519Df52Ba1765F2676c8E);
        uint256 protocolFee = 0;
        address linkTokenAddress = address(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
        address vrfWrapper = address(0x708701a1DfF4f478de54383E49a627eD4852C816);
        uint32 callbackGasLimit = 60_000;
        uint16 requestConfirmations = 3;
        uint256 linkFee = 0.5 ether;

        ProbaCompetitionFactory probaCompetitionFactory = new ProbaCompetitionFactory(
            protocolAddress,
            protocolFee,
            linkTokenAddress,
            vrfWrapper,
            linkFee,
            callbackGasLimit,
            requestConfirmations
        );

        console.log("Proba Competition Factory Contract deployed to Goerli at", address(probaCompetitionFactory));

        vm.stopBroadcast();
    }

    function test() public { } // sad hack to exclude file from `forge coverage`
}

contract DeployArbitrumProbaFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ETH_DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Arbitrum Setup for VRF v2
        address protocolAddress = address(0x0E5315780d39ce7AA64519Df52Ba1765F2676c8E);
        uint256 protocolFee = 0;
        address linkTokenAddress = address(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
        address vrfWrapper = address(0x2D159AE3bFf04a10A355B608D22BDEC092e934fa);
        uint256 linkFee = 0.3 ether;
        uint32 callbackGasLimit = 60_000;
        uint16 requestConfirmations = 10;

        ProbaCompetitionFactory probaCompetitionFactory = new ProbaCompetitionFactory(
            protocolAddress,
            protocolFee,
            linkTokenAddress,
            vrfWrapper,
            linkFee,
            callbackGasLimit,
            requestConfirmations
        );
        console.log("Proba Competition Factory Contract deployed to Arbitrum at", address(probaCompetitionFactory));

        vm.stopBroadcast();
    }

    function test() public { } // sad hack to exclude file from `forge coverage`
}
