// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";

import "./ProbaCompetitionFactory.sol";

/// @notice A competition contract where users can buy tickets to win a reward. Each ticket is
///   called an rxNFT and grants an equal chance of winning. At creation time, tickets are
///   denominated in either native or ERC20 tokens. rxNFTs are minted on demand upon payment
///   during the competition open window as determined by its duration. The reward is an
///   amount of ERC20 tokens or a single ERC721 token. After the competition duration, the
///   winner is determined via Chainlink VRFv2 and the reward can be claimed. A protocol fee is
///   calculated and charged, and the remaining proceeds can be claimed by the game creator.
///   However, if a minimum number of ticket sales is set and not met, there will be no
///   winner and the creator can get the reward refunded.
contract Competition is ERC721, VRFV2WrapperConsumerBase {
    using SafeERC20 for IERC20;

    /// @notice Possible payment types for buying competition tickets
    ///         - Native: Use the chain's native currency
    ///         - ERC20: Use the ERC20 token with contract address specified separately
    enum PaymentType {
        Native,
        ERC20
    }

    /// @notice Possible states of a Competition:
    ///         - New: Preview, tickets not being sold yet
    ///         - Open: Started, if there are remaining tickets and time, users can buy tickets
    ///         - Success: Competition over, winner can claim reward
    ///         - Failed: Minimum ticket sales not met within competition duration
    enum Status {
        New,
        Open,
        Success,
        Failed
    }

    /// @notice Possible actions of a RewardTransfer Event
    ///         - Deposit: Game creator deposits reward to start the competition
    ///         - Withdraw: Game creator withdraws reward due to minimum ticket sales not reached
    ///         - Claim: Winner claims reward after competition has determined a winner
    enum RewardAction {
        Deposit,
        Withdraw,
        Claim
    }

    /// @notice Possible reward types of a Competition:
    ///         - ERC20: Reward is ERC20 tokens
    ///         - ERC721: Reward is an ERC721 token
    enum RewardType {
        ERC20,
        ERC721
    }

    /// @notice Competition's RxNFT details
    struct RxNFT {
        /// @notice rxNFT Name
        string name;
        /// @notice rxNFT Symbol
        string symbol;
    }

    /// @notice Payment details for competition tickets
    struct Payment {
        /// @notice Type of token accepted as payment
        PaymentType paymentType;
        /// @notice If ERC20, contract address of token
        IERC20 token;
        /// @notice Price of each ticket, i.e. to mint 1 rxNFT
        uint256 ticketPrice;
    }

    /// @notice Competition Reward Details
    struct Reward {
        /// @notice Reward type (ERC20 / ERC721)
        RewardType rewardType;
        /// @notice Contract address of reward token
        address token;
        /// @notice Amount of reward tokens
        uint256 amount;
        /// @notice Token ID of ERC721 Reward
        uint256 tokenID;
    }

    /// @notice Competition limits
    struct Limits {
        /// @notice Minimum tickets to be minted, use 0 for no limit
        uint32 minTickets;
        /// @notice Maximum tickets to be minted, use 0xFFFFFFFF for no limit
        uint32 maxTickets;
        /// @notice Mint limit per wallet, use 0xFFFFFFFF for no limit
        uint32 limitPerWallet;
    }

    /// @notice Proba main factory contract. Provides protocol fee amounts and destination
    ProbaCompetitionFactory private immutable mainFactory;

    /// @notice Studio contract, emitted with most events in this contract
    address public immutable studio;

    /// @notice Ticket sales payment details
    Payment public payment;

    /// @notice Reward token details
    Reward public reward;

    /// @notice Competition limits
    Limits public limits;

    /// @notice Competition draw status
    Status public status = Status.New;

    /// @notice Duration in seconds of Competition
    uint64 public immutable durationSeconds;

    /// @notice Competition ends on this time (seconds since epoch) and can be
    ///         executed after this time by calling `executeCompetition()`
    uint256 public endTime;

    /// @notice Number of tickets (minted) sold so far
    uint32 public numTicketsSold;

    /// @notice Winning ticket ID, set when status == Success
    uint32 public winningTicket;

    /// @notice Whether ticket fees has been transfered after a successful draw
    bool private ticketFeesTransferred = false;

    /// @notice Whether ticket proceeds less fees has been transfered after a successful draw
    bool private ticketProceedsTransferred = false;

    /// @notice Whether LINK and reward have been transferred after a failed draw
    bool private linkAndRewardsWithdrawn = false;

    /// @notice Proba protocol fee charged on ticket proceeds, in basis points, eg. 30 for 0.3%.
    ///         This is fixed when the Competition starts and cannot be changed.
    uint256 private immutable protocolFee;

    /// @dev Divisor for basis points
    uint256 private constant BASIS_POINTS = 10_000;

    /// @dev In the context of this contract, we only need 1 random number
    uint32 private constant LINK_NUM_WORDS = 1;

    struct LinkInfo {
        /// @notice Chainlink token contract address
        IERC20 token;
        /// @notice Chainlink Fee required to fufill a VRFv2 request
        uint256 fee;
        /// @notice Maximum amount of gas that should be provided
        ///         for the Chainlink VRFv2 callback function
        uint32 callbackGasLimit;
        /// @notice Number of block confirmations to wait before the VRFv2 callback is executed
        uint16 requestConfirmations;
        /// @notice Number of random words requested from Chainlink VRFv2
        uint32 numWords;
    }

    LinkInfo private linkInfo;

    /// @notice Change in status, possible state changes for status
    /// - New -> Open: Reward deposited, competition started by game creator
    /// - Open -> Success: Duration over, winner successfully picked via VRF
    /// - Open -> Failed: Duration over, not enough tickets sold
    /// @param studio Address of the studio factory that created this competition
    /// @param status The new status of the competition
    event DrawStatus(address indexed studio, Status indexed status);

    /// @notice New game created
    /// @param studio Studio contract address
    /// @param rxNFT Name and Symbol of competition
    /// @param payment Payment details of Competition
    /// @param reward Reward details of Competition
    /// @param limits Competition limits
    /// @param durationSeconds Duration of competition in seconds
    /// @param description Description of Competition
    event NewCompetition(
        address indexed studio,
        RxNFT rxNFT,
        Payment payment,
        Reward reward,
        Limits limits,
        uint64 durationSeconds,
        string description
    );

    /// @notice gameCreator starts the game
    /// @param endTime Epoch time in seconds of when Competition will end
    event CompetitionStart(uint256 endTime);

    /// @notice Reward is transferred at start, and upon success / failure
    /// @param studio Studio contract address
    /// @param addr Address initiating reward action
    /// @param action Whether this is a deposit, claim or withdrawal
    /// @param rewardType Type of reward token
    /// @param rewardToken Reward token address
    /// @param amount Amount of reward token
    /// @param tokenID TokenID of reward token if ERC721
    event RewardTransfer(
        address indexed studio,
        address indexed addr,
        RewardAction action,
        RewardType rewardType,
        address indexed rewardToken,
        uint256 amount,
        uint256 tokenID
    );

    /// @notice Tickets have been minted
    /// @param studio Studio contract address
    /// @param addr Address that bought tickets
    /// @param numTickets Number of tickets minted
    event Mint(address indexed studio, address indexed addr, uint256 numTickets);

    /// @notice Draw executed, winner determined, when Chainlink VRFv2 coordinator injects randomness
    /// @param studio Studio contract address
    /// @param winner Winning address of the competition (owner of the winning tokenID)
    /// @param ticketID The ticketID deemed as the winning ticket
    /// @param requestID The requestID used when requesting for randomness to VRFv2
    /// @param randomness The random number returned from VRFv2
    /// @param numTicketsSold Total number of tickets sold / rxNFT minted
    event Executed(
        address indexed studio,
        address indexed winner,
        uint32 ticketID,
        uint256 requestID,
        uint256 randomness,
        uint32 numTicketsSold
    );

    /// @notice Protocol's fees from ticket proceeds transferred to protocol address
    /// @param paymentType Payment type of the Competition (Native, ERC20)
    /// @param paymentToken Payment token address (Null address when payment type is Native)
    /// @param protocol Proba protocol address receiving the fee
    /// @param amount Amount of PaymentType currency sent
    event ProtocolFeeTransfer(
        address indexed protocol, PaymentType indexed paymentType, address indexed paymentToken, uint256 amount
    );

    /// @notice Emitted when ticket proceeds less protocol fees is transferred to game creator
    /// @param studio Studio contract address
    /// @param gameCreator Game creator address
    /// @param paymentType Payment type of the Competition (Native, ERC20)
    /// @param paymentToken Payment token address (Null address when payment type is Native)
    /// @param amount Amount of PaymentType currency sent
    event TicketProceedsTransfer(
        address indexed studio,
        address indexed gameCreator,
        PaymentType paymentType,
        address indexed paymentToken,
        uint256 amount
    );

    /// @notice Bad parameters for competition creation
    /// @param param Parameter with invalid value:
    ///        - MIN: minTickets cannot be greater than maxTickets
    ///        - MAX: maxTickets cannot be 0
    ///        - LMT: limitPerWallet cannot be 0
    ///        - DUR: durationSeconds cannot be less than 1 minute
    ///        - PAY: payment token cannot be null address
    ///        - RWD: reward amount cannot be 0
    ///        - 721: rxNFT name / symbol cannot be empty
    ///        - LNK: LINK coordinator / token cannot be null address
    ///        - FEE: Proba protocol fee is invalid
    error InvalidParameters(string param);

    /// @notice Competition status is not ${status}
    /// @param status Expected competition status
    error InvalidStatus(Status status);

    /// @notice Caller is not the game creator
    error OnlyGameCreator();

    /// @notice Requires higher approval limits to transfer tokens
    /// @param token Token with insufficient allowance
    ///        - LNK: LINK token allowance is insufficient
    ///        - RWD: reward token allowance is insufficient
    ///        - NFT: reward NFT approval missing
    ///        - PAY: payment token allowance insufficient
    error InsufficientAllowance(string token);

    /// @notice Reward missing, can't deposit
    error InsufficientReward();

    /// @notice Wrong payment type called
    error InvalidPaymentType();

    /// @notice Wrong payment amount sent
    /// @param amount Amount of payment expected
    error InvalidPaymentAmount(uint256 amount);

    /// @notice You need to buy at least 1 ticket
    error CannotBuyNothing();

    /// @notice Can't buy more tickets than the competition has left
    error NoMoreTickets();

    /// @notice Sorry, the competition is over
    error CompetitionOver();

    /// @notice You have exceeded the number of tickets allowed per wallet
    error WalletLimitExceeded();

    /// @notice Competition is not ready for execution, as either:
    ///         - status is not Open (not started, ended or cancelled), or
    ///         - not due for execution (not past execution timestamp), or
    ///         - number of tickets sold has not yet hit the minimum
    error CannotExecute();

    /// @notice When executing the competition, the contract needs to have the
    ///         sufficient LINK token deposited (Chainlink Fee for requesting random number)
    error InsufficientLINK();

    /// @notice Must hold and call function with correct ticket IDs for refund
    error NotTicketHolder();

    /// @notice You must be the winner to claim the prize
    error NotWinner();

    /// @notice Reward / LINK / refund has already been sent
    error AlreadyTransferred();

    /// @dev Ensures competition is in required status
    /// @param _status Required status
    modifier onlyStatus(Status _status) {
        if (status != _status) {
            revert InvalidStatus(_status);
        }

        _;
    }

    /// @dev Initializes a new competition.
    /// @param _probaFactory Address of the main factory contract
    /// @param _studio Address of the studio factory contraact
    /// @param _description Competition description
    /// @param _rxNFT Name and Symbol of the competition (ERC721 token name and symbol)
    /// @param _payment Payment details of the Competition
    /// @param _reward Reward details of the Competition
    /// @param _limits Competition limits
    /// @param _durationSeconds Duration of the competition in seconds
    /// @param _linkToken Address of Chainlink LINK token
    /// @param _vrfWrapper Address of Chainlink VRFv2 Wrapper
    constructor(
        address _probaFactory,
        address _studio,
        string memory _description,
        RxNFT memory _rxNFT,
        Payment memory _payment,
        Reward memory _reward,
        Limits memory _limits,
        uint64 _durationSeconds,
        address _linkToken,
        address _vrfWrapper
    )
        ERC721(requireString(_rxNFT.name), requireString(_rxNFT.symbol))
        VRFV2WrapperConsumerBase(requireLinkAddress(_linkToken), requireLinkAddress(_vrfWrapper))
    {
        if (_limits.maxTickets < _limits.minTickets) revert InvalidParameters("MIN");
        if (_limits.maxTickets == 0) revert InvalidParameters("MAX");
        if (_limits.limitPerWallet == 0) revert InvalidParameters("LMT");
        if (_durationSeconds < 1 minutes) revert InvalidParameters("DUR");
        if (_studio == address(0)) revert InvalidParameters("STD");

        // If the payment type is ERC20, we will have to check if the payment token address
        // is a valid ERC20 contract (with decimals call)
        if (_payment.paymentType == PaymentType.ERC20) {
            if (address(_payment.token) == address(0)) {
                revert InvalidParameters("PAY");
            }

            IERC20Metadata(address(_payment.token)).decimals();
        }

        if (_reward.rewardType == RewardType.ERC20 && _reward.amount == 0) {
            revert InvalidParameters("RWD");
        }

        mainFactory = ProbaCompetitionFactory(_probaFactory);

        // Fix protocol address / fees to avoid e.g. fee changes during competition
        protocolFee = mainFactory.protocolFee();

        // It shouldn't be anywhere near but really bad things happens if protocolFee > 100%
        if (protocolFee > BASIS_POINTS) {
            revert InvalidParameters("FEE");
        }

        studio = _studio;

        payment = _payment;
        reward = _reward;
        limits = _limits;
        durationSeconds = _durationSeconds;

        linkInfo = LinkInfo({
            token: IERC20(_linkToken),
            fee: mainFactory.linkFee(),
            callbackGasLimit: mainFactory.linkCallbackGasLimit(),
            requestConfirmations: mainFactory.linkRequestConfirmations(),
            numWords: LINK_NUM_WORDS
        });

        // TODO: include more competition details
        emit NewCompetition(address(studio), _rxNFT, _payment, _reward, _limits, _durationSeconds, _description);
    }

    /// @notice Small function to validate super() ERC721 parameters
    function requireString(string memory str) internal pure returns (string memory) {
        if (bytes(str).length == 0) {
            revert InvalidParameters("721");
        }

        return str;
    }

    /// @notice Small function to validate super() address parameters
    function requireLinkAddress(address addr) internal pure returns (address) {
        if (addr == address(0)) {
            revert InvalidParameters("LNK");
        }

        return addr;
    }

    /// @notice Owner address of the Studio Factory Contract
    function gameCreator() internal view returns (address) {
        return StudioCompetitionFactory(studio).owner();
    }

    /// @dev Sets status, emits changed event
    function setStatus(Status _status) internal {
        status = _status;
        emit DrawStatus(studio, status);
    }

    /// @notice Starts the competition, contract will transfer the reward from
    ///         the gameCreator wallet. Competition status must be 'New'
    /// @dev Assumes linkToken and rewardToken are not malicious and causing reentrancy
    function startCompetition() external onlyStatus(Status.New) {
        if (msg.sender != gameCreator()) {
            revert OnlyGameCreator();
        }

        if (linkInfo.token.allowance(msg.sender, address(this)) < linkInfo.fee) {
            revert InsufficientAllowance("LNK");
        }

        setStatus(Status.Open);
        endTime = block.timestamp + durationSeconds;

        // Transfer LINK token from gameCreator for requesting random number
        linkInfo.token.safeTransferFrom(msg.sender, address(this), linkInfo.fee);

        // Transfer Reward from gameCreator to this contract
        if (reward.rewardType == RewardType.ERC20) {
            uint256 rewardAmount = reward.amount;
            IERC20 rewardToken = IERC20(reward.token);

            if (rewardToken.allowance(msg.sender, address(this)) < rewardAmount) {
                revert InsufficientAllowance("RWD");
            }

            if (rewardToken.balanceOf(msg.sender) < rewardAmount) {
                revert InsufficientReward();
            }

            rewardToken.safeTransferFrom(msg.sender, address(this), rewardAmount);
        } else {
            uint256 rewardTokenID = reward.tokenID;
            IERC721 rewardToken = IERC721(reward.token);

            if (rewardToken.getApproved(rewardTokenID) != address(this)) {
                revert InsufficientAllowance("RWD");
            }

            rewardToken.transferFrom(msg.sender, address(this), rewardTokenID);
        }

        emit RewardTransfer(
            studio, msg.sender, RewardAction.Deposit, reward.rewardType, reward.token, reward.amount, reward.tokenID
        );
        emit CompetitionStart(endTime);
    }

    /// @dev Verifies the conditions for purchasing tickets
    /// @param numTickets The number of tickets to verify for purchase
    function _verifyBuyConditions(uint32 numTickets) internal view {
        if (numTickets == 0) {
            revert CannotBuyNothing();
        }

        if (numTicketsSold + numTickets > limits.maxTickets) {
            revert NoMoreTickets();
        }

        if (block.timestamp > endTime) {
            revert CompetitionOver();
        }

        if (balanceOf(msg.sender) + numTickets > limits.limitPerWallet) {
            revert WalletLimitExceeded();
        }
    }

    /// @notice Buy tickets for the competition. If payment type is native, tokens must be sent
    ///         with call, otherwise ERC20 allowance must have been set.
    /// @dev The competition must be Open
    /// @param numTickets The number of tickets to mint
    function buyTickets(uint32 numTickets) external payable onlyStatus(Status.Open) {
        _verifyBuyConditions(numTickets);

        _mintAndEmit(numTickets);

        uint256 totalPrice = payment.ticketPrice * numTickets;

        if (payment.paymentType == PaymentType.Native) {
            if (msg.value != totalPrice) {
                revert InvalidPaymentAmount(totalPrice);
            }
        } else {
            IERC20 _paymentToken = payment.token;

            if (msg.value != 0) {
                revert InvalidPaymentAmount(0);
            }

            if (_paymentToken.allowance(msg.sender, address(this)) < totalPrice) {
                revert InsufficientAllowance("PAY");
            }

            _paymentToken.safeTransferFrom(msg.sender, address(this), totalPrice);
        }
    }

    /// @dev Internal function to mint tickets and manage the associated state
    /// @param numTickets The number of tickets to mint
    function _mintAndEmit(uint32 numTickets) internal {
        for (uint32 i = 0; i < numTickets;) {
            numTicketsSold += 1;
            // Token IDs start from 1
            _mint(msg.sender, numTicketsSold);

            unchecked {
                i++;
            } // bounded by numTickets
        }

        emit Mint(studio, msg.sender, numTickets);
    }

    /// @notice Is competition ready for randomness to be injected to conduct the draw?
    /// @return 'true' if `status` is Open and last block timestamp > `endTime`
    function canExecute() internal view returns (bool) {
        // Competition must be active or minting / buying period must be over
        return status == Status.Open && block.timestamp > endTime;
    }

    /// @notice Conduct the draw for the competition by fetching a random number with Chainlink VRFv2
    /// @dev This function requires the contract to have enough LINK tokens to pay for the VRFv2 fee
    function executeCompetition() external {
        if (!canExecute()) {
            revert CannotExecute();
        }

        if (numTicketsSold == 0 || numTicketsSold < limits.minTickets || block.timestamp > endTime + 30 days) {
            setStatus(Status.Failed);
        } else {
            requestRandomness(linkInfo.callbackGasLimit, linkInfo.requestConfirmations, linkInfo.numWords);
        }
    }

    /// @dev Handle the randomness provided by Chainlink VRFv2, determine the winner of the
    ///      competition. This function should only be called by the VRFv2 Coordinator or the
    ///      designated randomness provider in response to a randomness request
    /// @param requestID The unique identifier for the randomness request
    /// @param randomWords An array of random numbers returned by Chainlink VRFv2,
    ///                    we utilize only the first number to determine the winner.
    function fulfillRandomWords(uint256 requestID, uint256[] memory randomWords)
        internal
        override
        onlyStatus(Status.Open)
    {
        uint256 randomness = randomWords[0];
        // winning ticket ID range is [1, numTicketsSold]
        // numTicketsSold can never be 0 because executeCompetition would have set status to Failed
        winningTicket = uint32(randomness % numTicketsSold + 1);
        address winner = ownerOf(winningTicket);

        setStatus(Status.Success);

        emit Executed(studio, winner, winningTicket, requestID, randomness, numTicketsSold);
    }

    /// @dev Avoid potential copy and paste / rounding errors by having a single function to
    ///      calculate fees & proceeds.
    function calculateFeesAndProceeds() internal view returns (uint256 fees, uint256 proceeds) {
        uint256 totalSales = payment.ticketPrice * numTicketsSold;

        // Calculate the actual protocol fee and remaining amount after the fee
        fees = totalSales * protocolFee / BASIS_POINTS;
        proceeds = totalSales - fees;
    }

    /// @notice Transfers protocol fees to protocol address. Note that the address can be updated
    ///         up until this point.
    function transferFees() external onlyStatus(Status.Success) {
        if (ticketFeesTransferred) {
            revert AlreadyTransferred();
        }

        ticketFeesTransferred = true;

        (uint256 fees, /* uint256 _proceeds */ ) = calculateFeesAndProceeds();
        address protocolAddress = mainFactory.protocolAddress();

        if (payment.paymentType == PaymentType.ERC20) {
            IERC20(payment.token).safeTransfer(protocolAddress, fees);
        } else {
            payable(protocolAddress).transfer(fees);
        }

        emit ProtocolFeeTransfer(protocolAddress, payment.paymentType, address(payment.token), fees);
    }

    /// @notice Transfers ticket proceeds less fees and remaining LINK to game creator. Note that
    ///         the studio can change the game creator up until this point.
    function transferProceeds() external onlyStatus(Status.Success) {
        if (ticketProceedsTransferred) {
            revert AlreadyTransferred();
        }

        ticketProceedsTransferred = true;

        ( /* uint256 _fees */ , uint256 proceeds) = calculateFeesAndProceeds();
        address _gameCreator = gameCreator();

        if (payment.paymentType == PaymentType.ERC20) {
            IERC20(payment.token).safeTransfer(_gameCreator, proceeds);
        } else {
            payable(_gameCreator).transfer(proceeds);
        }

        // Transfer remaining LINK token back to gameCreator
        uint256 linkBalance = linkInfo.token.balanceOf(address(this));
        if (linkBalance > 0) {
            linkInfo.token.safeTransfer(_gameCreator, linkBalance);
        }

        emit TicketProceedsTransfer(studio, _gameCreator, payment.paymentType, address(payment.token), proceeds);
    }

    /// @dev Send rewards to recipient
    function transferRewardTo(address recipient) internal {
        if (reward.rewardType == RewardType.ERC20) {
            IERC20 rewardToken = IERC20(reward.token);
            rewardToken.safeTransfer(recipient, reward.amount);
        } else {
            IERC721 rewardToken = IERC721(reward.token);
            rewardToken.safeTransferFrom(address(this), recipient, reward.tokenID);
        }
    }

    /// @notice Claim reward if competition is successful and you have the winning ticket
    /// @dev Will not cause reentrancy issues if rewardToken is safe
    function claimReward() external onlyStatus(Status.Success) {
        address winner = _ownerOf(winningTicket);

        if (msg.sender != winner) {
            revert NotWinner();
        }

        // Burn the winning rxNFT / ticket
        _burn(winningTicket);

        transferRewardTo(winner);

        emit RewardTransfer(
            studio, winner, RewardAction.Claim, reward.rewardType, reward.token, reward.amount, reward.tokenID
        );
    }

    /// @notice Withdraws LINK and rewards from the contract, if the competition failed. Only
    ///         the game creator can call this.
    /// @dev Will not cause reentrancy issues if linkToken and rewardToken is safe
    function withdrawFunds() external onlyStatus(Status.Failed) {
        if (msg.sender != gameCreator()) {
            revert OnlyGameCreator();
        }

        if (linkAndRewardsWithdrawn) {
            revert AlreadyTransferred();
        }

        linkAndRewardsWithdrawn = true;

        // Send LINK back to gameCreator, if any
        uint256 linkBalance = linkInfo.token.balanceOf(address(this));
        if (linkBalance > 0) {
            linkInfo.token.safeTransfer(gameCreator(), linkBalance);
        }

        transferRewardTo(gameCreator());

        emit RewardTransfer(
            studio, gameCreator(), RewardAction.Withdraw, reward.rewardType, reward.token, reward.amount, reward.tokenID
        );
    }

    /// @notice Claim a refund if the draw failed to reach the minimum ticket sales at the end of
    ///         competiion duration. A list of ticket IDs must be provide which are then burnt.
    ///         Competition status should be 'Failed'
    /// @dev Assumes paymentToken is safe
    function claimRefund(uint256[] memory tickets) external onlyStatus(Status.Failed) {
        uint256 numTickets = tickets.length;

        // Burn the minted rxNFTs / tickets of the sender
        // If the owner of Token ID is not the sender, we will revert the transaction
        for (uint256 i = 0; i < numTickets;) {
            uint256 id = tickets[i];
            if (msg.sender != ownerOf(id)) {
                revert NotTicketHolder();
            }

            _burn(id);

            unchecked {
                i++;
            } // bounded by numTickets
        }

        // successfully burnt all tickets, refund price * tickets
        uint256 refundAmount = payment.ticketPrice * numTickets;

        if (payment.paymentType == PaymentType.ERC20) {
            payment.token.safeTransfer(msg.sender, refundAmount);
        } else {
            payable(msg.sender).transfer(refundAmount);
        }
    }
}
