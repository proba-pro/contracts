// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { Test, console2 } from "forge-std/Test.sol";

import { Competition } from "../contracts/Competition.sol";

uint256 constant BASIS_POINTS = 10_000;

contract MockProba {
    address public protocolAddress = address(100);
    uint256 public protocolFee = 137; // 1.37% also a nice prime number
    uint256 public linkFee = 1;
    uint16 public linkRequestConfirmations = 1;
    uint32 public linkCallbackGasLimit = 60_000;
}

contract BadProba {
    uint256 public protocolFee = 10_001;
}

contract MockStudio {
    address public owner = address(101);
}

contract MockLink is ERC20("Link", "LINK") {
    function transferAndCall(address, uint256, bytes memory) public returns (bool) { }
}

contract MockVRFWrapper {
    uint256 public lastRequestId;

    function calculateRequestPrice(uint32) public view returns (uint256) { }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }
}

abstract contract CompetitionTest is Test {
    Competition public competition;
    MockStudio public studio = new MockStudio();
    MockProba public proba = new MockProba();
    ERC20 public linkToken = new MockLink();
    MockVRFWrapper vrfWrapper = new MockVRFWrapper();

    string description = "A Test Competition";

    Competition.RxNFT rxNFT = Competition.RxNFT({ name: "TestCompetition", symbol: "TEST" });

    Competition.Payment public payment;
    Competition.Reward public reward;

    Competition.Limits public limits = Competition.Limits({ minTickets: 1, maxTickets: 256, limitPerWallet: 2 });

    uint64 durationSeconds = 3600;

    function setUp() public virtual {
        payment.ticketPrice = 0.1 ether;

        test_setupPayment();
        test_setupReward();
    }

    function test_internal() public {
        CompetitionInternalTest internalTest = new CompetitionInternalTest();

        internalTest._requireString("GOOD");
        expectRevertInvalidParameters("721");
        internalTest._requireString("");

        internalTest._requireLinkAddress(address(1));
        expectRevertInvalidParameters("LNK");
        internalTest._requireLinkAddress(address(0));
    }

    function setupCompetition() internal {
        competition = new Competition(
            address(proba),
            address(studio),
            "",
            rxNFT,
            payment,
            reward,
            limits,
            durationSeconds,
            address(linkToken),
            address(vrfWrapper)
        );
    }

    /// These setup functions are prefixed with `test_` so that they are not included in the forge
    /// coverage report. They are overriden by the test contracts below that sets up the different
    /// payment / reward types.
    function test_setupPayment() internal virtual;
    function test_setupReward() internal virtual;

    function approveReward() internal virtual;
    function paymentBalance(address) internal virtual returns (uint256);
    function hasReward(address) internal virtual returns (bool);

    function buyerDeal(address wallet, uint256 amount) internal {
        if (address(payment.token) != address(0)) {
            deal(address(payment.token), wallet, amount);
        } else {
            deal(wallet, amount);
        }
    }

    function test_CompetitionStatus() public {
        setupCompetition();
        assert(competition.status() == Competition.Status.New);
    }

    function test_CompetitionConstructionReverts() public {
        uint256 snapshot = vm.snapshot();

        rxNFT.name = "";
        expectRevertInvalidParameters("721");
        setupCompetition();

        vm.revertTo(snapshot);
        rxNFT.symbol = "";
        expectRevertInvalidParameters("721");
        setupCompetition();

        vm.revertTo(snapshot);
        linkToken = MockLink(address(0));
        expectRevertInvalidParameters("LNK");
        setupCompetition();

        vm.revertTo(snapshot);
        vrfWrapper = MockVRFWrapper(address(0));
        expectRevertInvalidParameters("LNK");
        setupCompetition();

        vm.revertTo(snapshot);
        limits.minTickets = 0xFFFF;
        expectRevertInvalidParameters("MIN");
        setupCompetition();

        vm.revertTo(snapshot);
        limits.minTickets = 0;
        limits.maxTickets = 0;
        expectRevertInvalidParameters("MAX");
        setupCompetition();

        vm.revertTo(snapshot);
        limits.limitPerWallet = 0;
        expectRevertInvalidParameters("LMT");
        setupCompetition();

        vm.revertTo(snapshot);
        durationSeconds = 30;
        expectRevertInvalidParameters("DUR");
        setupCompetition();

        vm.revertTo(snapshot);
        studio = MockStudio(address(0));
        expectRevertInvalidParameters("STD");
        setupCompetition();

        if (payment.paymentType == Competition.PaymentType.ERC20) {
            vm.revertTo(snapshot);
            payment.token = IERC20(address(0));
            expectRevertInvalidParameters("PAY");
            setupCompetition();
        }

        if (reward.rewardType == Competition.RewardType.ERC20) {
            vm.revertTo(snapshot);
            reward.amount = 0;
            expectRevertInvalidParameters("RWD");
            setupCompetition();
        }

        vm.revertTo(snapshot);
        proba = MockProba(address(new BadProba()));
        expectRevertInvalidParameters("FEE");
        setupCompetition();
    }

    /// Happy path for starting a competition
    function startCompetition() internal {
        deal(address(linkToken), studio.owner(), 1 ether);

        vm.startPrank(studio.owner());
        linkToken.approve(address(competition), 1 ether);
        vm.stopPrank();

        approveReward();

        vm.startPrank(studio.owner());
        competition.startCompetition();
        vm.stopPrank();
    }

    /// Simulates `wallet` buying `numTickets` tickets and spending or approving `amount` tokens
    function buyTickets(address wallet, uint256 amount, uint32 numTickets) public virtual;

    /// start and finish a competition, by having `actors` wallets buy tickets and executing
    /// the competition with `randomNumber`. The comppetition should be in either a Success or
    /// Failed state after this function is called.
    function finishCompetition(uint8 actors, uint256 randomNumber) public {
        uint256 requestID = 1;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = randomNumber;

        if (competition.status() == Competition.Status.New) {
            startCompetition();
        }

        for (uint160 i = 1000; i < 1000 + uint160(actors); i++) {
            buyerDeal(address(i), 0.1 ether);
            this.buyTickets(address(i), 0.1 ether, 1);
        }

        vm.warp(block.timestamp + competition.durationSeconds() + 1);

        competition.executeCompetition();

        if (competition.status() != Competition.Status.Failed) {
            vm.startPrank(address(vrfWrapper));
            competition.rawFulfillRandomWords(requestID, randomWords);
            vm.stopPrank();
        }
    }

    function test_StartCompetitionReverts() public {
        setupCompetition();

        vm.expectRevert(Competition.OnlyGameCreator.selector);
        competition.startCompetition();

        // set msg.sender to competition creator
        vm.startPrank(studio.owner());
        {
            vm.expectRevert(abi.encodeWithSelector(Competition.InsufficientAllowance.selector, "LNK"));
            competition.startCompetition();

            linkToken.approve(address(competition), 1 ether);
            deal(address(linkToken), studio.owner(), 1 ether);

            vm.expectRevert(abi.encodeWithSelector(Competition.InsufficientAllowance.selector, "RWD"));
            competition.startCompetition();
        }
        vm.stopPrank();

        if (reward.rewardType == Competition.RewardType.ERC20) {
            deal(address(linkToken), studio.owner(), 1 ether);
            approveReward();
            deal(address(reward.token), studio.owner(), 0); // remove reward from studio

            vm.startPrank(studio.owner());
            {
                linkToken.approve(address(competition), 1 ether);
                vm.expectRevert(Competition.InsufficientReward.selector);
                competition.startCompetition();
            }
            vm.stopPrank();
        }
    }

    function test_StartCompetition() public {
        setupCompetition();
        startCompetition();

        assert(competition.status() == Competition.Status.Open);
    }

    function test_BuyTicketsReverts() public {
        setupCompetition();

        buyerDeal(address(1000), 0.1 ether);
        expectRevertStatus(Competition.Status.Open);
        // call "externally" for expectRevert to check the right call
        this.buyTickets(address(1000), 0.1 ether, 1);

        startCompetition();

        vm.expectRevert();
        this.buyTickets(address(1000), 0, 1);

        if (payment.paymentType == Competition.PaymentType.ERC20) {
            vm.expectRevert(abi.encodeWithSelector(Competition.InvalidPaymentAmount.selector, 0));
            competition.buyTickets{ value: 0.1 ether }(1);

            buyerDeal(address(1000), 0);
            vm.expectRevert(abi.encodeWithSelector(Competition.InsufficientAllowance.selector, "PAY"));
            competition.buyTickets(1);
        }

        vm.warp(block.timestamp + competition.durationSeconds() + 1);
        vm.expectRevert(Competition.CompetitionOver.selector);
        this.buyTickets(address(1000), 0.1 ether, 1);
    }

    function test_BuyTicketLimits() public {
        setupCompetition();
        startCompetition();

        vm.expectRevert(Competition.CannotBuyNothing.selector);
        this.buyTickets(address(1000), 0, 0);

        buyerDeal(address(1000), 0.3 ether);
        vm.expectRevert(Competition.WalletLimitExceeded.selector);
        this.buyTickets(address(1000), 0.3 ether, 3);

        buyerDeal(address(1000), 25.7 ether);
        vm.expectRevert(Competition.NoMoreTickets.selector);
        this.buyTickets(address(1000), 25.7 ether, 257);

        buyerDeal(address(1000), 0.2 ether);
        this.buyTickets(address(1000), 0.2 ether, 2);

        buyerDeal(address(1000), 0.2 ether);
        vm.expectRevert(Competition.WalletLimitExceeded.selector);
        this.buyTickets(address(1000), 0.2 ether, 2);

        for (uint160 i = 1001; i <= 1003; i++) {
            buyerDeal(address(i), 0.2 ether);
            this.buyTickets(address(i), 0.2 ether, 2);
        }

        buyerDeal(address(1004), 24.9 ether);
        vm.expectRevert(Competition.NoMoreTickets.selector);
        this.buyTickets(address(1004), 24.9 ether, 249);
    }

    function test_BuyTickets() public {
        setupCompetition();
        startCompetition();

        buyerDeal(address(1000), 0.2 ether);
        this.buyTickets(address(1000), 0.2 ether, 2);

        assertEq(competition.ownerOf(1), address(1000));
        assertEq(competition.ownerOf(2), address(1000));
    }

    function test_ExecuteCompetition() public {
        setupCompetition();

        vm.expectRevert(Competition.CannotExecute.selector);
        competition.executeCompetition();

        startCompetition();

        vm.expectRevert(Competition.CannotExecute.selector);
        competition.executeCompetition();

        vm.warp(block.timestamp + competition.durationSeconds());

        vm.expectRevert(Competition.CannotExecute.selector);
        competition.executeCompetition();

        vm.warp(block.timestamp + competition.durationSeconds() + 1);

        competition.executeCompetition();

        assert(competition.status() == Competition.Status.Failed);
    }

    function test_FulfillRandomWordsReverts() public {
        setupCompetition();

        uint256 requestID = 1;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42;

        vm.startPrank(address(vrfWrapper));
        expectRevertStatus(Competition.Status.Open);
        competition.rawFulfillRandomWords(requestID, randomWords);
        vm.stopPrank();

        startCompetition();

        vm.warp(block.timestamp + competition.durationSeconds() + 1);
        competition.executeCompetition();

        // fail because numTicketsSold == 0
        assert(competition.status() == Competition.Status.Failed);

        vm.startPrank(address(vrfWrapper));
        expectRevertStatus(Competition.Status.Open);
        competition.rawFulfillRandomWords(requestID, randomWords);
        vm.stopPrank();
    }

    function test_FulfillRandomWords() public {
        setupCompetition();

        vm.expectEmit(true, true, true, true);
        emit DrawStatus(address(studio), Competition.Status.Success);

        vm.expectEmit(true, true, true, true);
        emit Executed(address(studio), address(1000), 1, 1, 42, 1);

        this.finishCompetition(1, 42);

        assert(competition.status() == Competition.Status.Success);
        assertEq(competition.winningTicket(), 1);
    }

    function test_TransferFeesAndProceedsReverts() public {
        setupCompetition();

        expectRevertStatus(Competition.Status.Success);
        competition.transferFees();

        expectRevertStatus(Competition.Status.Success);
        competition.transferProceeds();

        finishCompetition(0, 42);

        expectRevertStatus(Competition.Status.Success);
        competition.transferFees();

        expectRevertStatus(Competition.Status.Success);
        competition.transferProceeds();
    }

    /// forge-config: default.fuzz.runs = 8
    function test_transferFeesAndProceeds(uint8 buyers) public {
        setupCompetition();

        vm.assume(buyers > 0);

        finishCompetition(buyers, 42);

        uint256 totalSales = payment.ticketPrice * buyers;
        uint256 fees = totalSales * proba.protocolFee() / BASIS_POINTS;
        uint256 proceeds = totalSales - fees;

        competition.transferFees();
        competition.transferProceeds();
        assertEq(paymentBalance(address(100)), fees);
        assertEq(paymentBalance(address(101)), proceeds);

        vm.expectRevert(Competition.AlreadyTransferred.selector);
        competition.transferFees();
        vm.expectRevert(Competition.AlreadyTransferred.selector);
        competition.transferProceeds();
    }

    function test_ClaimReward() public {
        setupCompetition();

        expectRevertStatus(Competition.Status.Success);
        competition.claimReward();

        startCompetition();

        expectRevertStatus(Competition.Status.Success);
        competition.claimReward();

        finishCompetition(2, 42);

        // 2 tickets sold, Winning ticket is #1
        assertEq(competition.winningTicket(), 1);

        vm.expectRevert(Competition.NotWinner.selector);
        competition.claimReward();

        uint256 snapshot = vm.snapshot();
        {
            vm.startPrank(address(1000));
            {
                competition.claimReward();
                assert(hasReward(address(1000)));

                vm.expectRevert(Competition.NotWinner.selector);
                competition.claimReward();
            }
            vm.stopPrank();
        }
        vm.revertTo(snapshot);

        vm.startPrank(address(1000));
        {
            // Give away winning ticket
            competition.transferFrom(address(1000), address(1001), 1);

            vm.expectRevert(Competition.NotWinner.selector);
            competition.claimReward();
        }
        vm.stopPrank();

        vm.startPrank(address(1001));
        {
            // Claiming with winning ticket
            competition.claimReward();
            assert(hasReward(address(1001)));

            vm.expectRevert(Competition.NotWinner.selector);
            competition.claimReward();
        }
        vm.stopPrank();
    }

    function test_WithdrawFunds() public {
        limits.minTickets = 2;

        setupCompetition();

        expectRevertStatus(Competition.Status.Failed);
        competition.withdrawFunds();

        startCompetition();

        expectRevertStatus(Competition.Status.Failed);
        competition.withdrawFunds();

        uint256 snapshot = vm.snapshot();
        {
            finishCompetition(2, 42);
            expectRevertStatus(Competition.Status.Failed);
            competition.withdrawFunds();
        }
        vm.revertTo(snapshot);

        finishCompetition(1, 42); // did not meet minTickets

        vm.expectRevert(Competition.OnlyGameCreator.selector);
        competition.withdrawFunds();

        vm.startPrank(address(101));
        {
            competition.withdrawFunds();
            assert(hasReward(address(101)));

            vm.expectRevert(Competition.AlreadyTransferred.selector);
            competition.withdrawFunds();
        }
        vm.stopPrank();
    }

    function test_ClaimRefund() public {
        limits.minTickets = 2;

        setupCompetition();

        uint256[] memory tickets = new uint256[](1);
        tickets[0] = 1;

        expectRevertStatus(Competition.Status.Failed);
        competition.claimRefund(tickets);

        startCompetition();

        expectRevertStatus(Competition.Status.Failed);
        competition.claimRefund(tickets);

        uint256 snapshot = vm.snapshot();
        {
            finishCompetition(2, 42);
            expectRevertStatus(Competition.Status.Failed);
            competition.claimRefund(tickets);
        }
        vm.revertTo(snapshot);

        finishCompetition(1, 42); // did not meet minTickets

        vm.expectRevert(Competition.NotTicketHolder.selector);
        competition.claimRefund(tickets);

        vm.startPrank(address(1000));
        {
            competition.claimRefund(tickets);
            assertEq(paymentBalance(address(1000)), 0.1 ether);

            vm.expectRevert(); // Invalid token ID due to ticket being burnt
            competition.claimRefund(tickets);
        }
        vm.stopPrank();
    }

    function test_Failsafe() public {
        setupCompetition();
        startCompetition();

        buyerDeal(address(1000), 0.1 ether);
        this.buyTickets(address(1000), 0.1 ether, 1);

        vm.warp(block.timestamp + competition.durationSeconds() + 1);
        competition.executeCompetition();
        assert(competition.status() == Competition.Status.Open);

        vm.warp(block.timestamp + competition.durationSeconds() + 31 days);
        competition.executeCompetition();
        assert(competition.status() == Competition.Status.Failed);
    }

    function expectRevertInvalidParameters(string memory param) internal {
        vm.expectRevert(abi.encodeWithSelector(Competition.InvalidParameters.selector, param));
    }

    function expectRevertStatus(Competition.Status status) internal {
        vm.expectRevert(abi.encodeWithSelector(Competition.InvalidStatus.selector, status));
    }

    event DrawStatus(address indexed, Competition.Status indexed);
    event Executed(address indexed, address indexed, uint32, uint256, uint256, uint32);
}

abstract contract NativePayment is CompetitionTest {
    function test_setupPayment() internal override {
        payment.paymentType = Competition.PaymentType.Native;
    }

    function paymentBalance(address addr) internal view override returns (uint256) {
        return addr.balance;
    }

    function buyTickets(address wallet, uint256 amount, uint32 numTickets) public override {
        vm.startPrank(wallet);
        competition.buyTickets{ value: amount }(numTickets);
        vm.stopPrank();
    }
}

abstract contract ERC20Payment is CompetitionTest {
    function test_setupPayment() internal override {
        payment.paymentType = Competition.PaymentType.ERC20;
        payment.token = new MockERC20("Payment", "PAY");
    }

    function paymentBalance(address addr) internal view override returns (uint256) {
        return payment.token.balanceOf(addr);
    }

    function buyTickets(address wallet, uint256 amount, uint32 numTickets) public override {
        vm.startPrank(wallet);
        payment.token.approve(address(competition), amount);
        competition.buyTickets(numTickets);
        vm.stopPrank();
    }
}

abstract contract ERC20Reward is CompetitionTest {
    ERC20 rewardToken;

    function test_setupReward() internal override {
        rewardToken = new MockERC20("Reward", "RWD");
        reward.rewardType = Competition.RewardType.ERC20;
        reward.token = address(rewardToken);
        reward.amount = 1 ether;
        reward.tokenID = 0;
        deal(address(reward.token), studio.owner(), 1 ether);
    }

    function approveReward() internal override {
        vm.startPrank(studio.owner());
        rewardToken.approve(address(competition), 1 ether);
        vm.stopPrank();
    }

    function hasReward(address addr) internal view override returns (bool) {
        return ERC20(reward.token).balanceOf(addr) == reward.amount;
    }
}

abstract contract ERC721Reward is CompetitionTest, ERC721("Reward", "RWD") {
    function test_setupReward() internal override {
        reward.rewardType = Competition.RewardType.ERC721;
        reward.token = address(this); // The test contract is the NFT contract
        reward.tokenID = 42;
        _mint(studio.owner(), 42);
    }

    function approveReward() internal override {
        vm.startPrank(studio.owner());
        this.approve(address(competition), 42);
        vm.stopPrank();
    }

    function hasReward(address addr) internal view override returns (bool) {
        return ERC721(reward.token).balanceOf(addr) == 1;
    }
}

contract NativePaymentERC20RewardCompetitionTest is NativePayment, ERC20Reward { }

contract NativePaymentERC721RewardCompetitionTest is NativePayment, ERC721Reward { }

contract ERC20PaymentERC20RewardCompetitionTest is ERC20Payment, ERC20Reward { }

contract ERC20PaymentERC721RewardCompetitionTest is ERC20Payment, ERC721Reward { }

/// Exposes internal functions for testing
contract CompetitionInternalTest is Competition {
    constructor()
        Competition(
            address(new MockProba()),
            address(new MockStudio()),
            "",
            Competition.RxNFT({ name: "TestCompetition", symbol: "TEST" }),
            Competition.Payment({
                paymentType: Competition.PaymentType.Native,
                token: ERC20(address(0)),
                ticketPrice: 0.1 ether
            }),
            Competition.Reward({
                rewardType: Competition.RewardType.ERC20,
                token: address(new MockERC20("", "")),
                amount: 1 ether,
                tokenID: 0
            }),
            Competition.Limits({ minTickets: 1, maxTickets: 256, limitPerWallet: 2 }),
            3600,
            address(new MockLink()),
            address(new MockVRFWrapper())
        )
    { }

    function _requireString(string memory str) public pure returns (string memory) {
        return requireString(str);
    }

    function _requireLinkAddress(address addr) public pure returns (address) {
        return requireLinkAddress(addr);
    }
}
