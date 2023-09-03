// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test } from "forge-std/Test.sol";

import { Competition } from "../contracts/Competition.sol";
import { StudioCompetitionFactory } from "../contracts/StudioCompetitionFactory.sol";

contract MockProba {
    address public protocolAddress;
    address public protocolFee;
    uint256 public linkFee = 1;
    uint16 public linkRequestConfirmations = 1;
    uint32 public linkCallbackGasLimit = 60_000;
    ERC20 public linkToken = new MockERC20("Link", "LINK");
    address public vrfWrapper = address(50);
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }
}

contract StudioCompetitionFactoryTest is Test {
    MockProba proba = new MockProba();
    StudioCompetitionFactory studio;
    address owner = address(100);

    Competition.Limits public limits;
    Competition.Payment public payment;
    Competition.Reward public reward;

    function setUp() public virtual {
        studio = new StudioCompetitionFactory("Studio", address(proba), owner);
    }

    function test_Owner() public {
        assertEq(studio.owner(), owner);
    }

    function test_CreateCompetition() public {
        Competition.RxNFT memory rxNFT = Competition.RxNFT({ name: "SomeCompetition", symbol: "SOME" });

        payment.paymentType = Competition.PaymentType.Native;
        payment.ticketPrice = 0.1 ether;

        reward.rewardType = Competition.RewardType.ERC20;
        reward.token = address(new MockERC20("Reward", "RWD"));
        reward.amount = 1 ether;

        limits.minTickets = 1;
        limits.maxTickets = 8;
        limits.limitPerWallet = 2;

        vm.expectEmit(false, true, true, true); // can't predict competition address
        emit NewCompetition(address(0), "SomeCompetition", "A new competition");
        studio.createCompetition("A new competition", rxNFT, payment, reward, limits, 3600);
    }

    // Solidity/NatSpec bug prevents referring to fully qualified event names e.g.
    // StudioCompetitionFactory.NewCompetition
    event NewCompetition(address indexed, string, string);
}
