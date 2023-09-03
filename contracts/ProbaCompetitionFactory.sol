// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "./StudioCompetitionFactory.sol";

/// @notice Top Level Factory to create Studio Competition Factories.
contract ProbaCompetitionFactory is Ownable {
    /// List of admins that can create
    mapping(address => bool) public admins;

    /// @notice Fees from ticket sales go here
    address public protocolAddress;

    /// @notice Protocol fee charged on ticket sales basis points, e.g. 30 = 0.3%
    uint256 public protocolFee;

    /// @notice Chainlink's token address
    address public immutable linkToken;
    /// @notice Chainlink's VRFv2 Wrapper address
    address public immutable vrfWrapper;
    /// @notice Chainlink's VRFv2 Callback Gas Limit
    uint32 public linkCallbackGasLimit;
    /// @notice Chainlink's VRFv2 Request Confirmations
    uint16 public immutable linkRequestConfirmations;
    /// @notice Chainlink's fee fufill a VRFv2 request
    uint256 public linkFee;

    /// @notice Emitted when a new studio factory contract is created
    /// @param studioFactory Studio factory contract address
    /// @param creator The creator address of studio factory address
    /// @param name Name of the studio
    /// @param description Description of the studio
    event NewStudio(address indexed studioFactory, address indexed creator, string name, string description);

    /// @notice Protocol fee changed
    /// @param fee The new fee value
    event ProtocolFee(uint256 indexed fee);

    /// @notice Protocol address for fee destination changed
    /// @param addr The new fee address
    event ProtocolFeeAddress(address indexed addr);

    /// @notice Emitted when the Chainlink fee is changed
    /// @param fee The new fee value
    event LinkFee(uint256 indexed fee);

    // @notice Emitted when the Chainlink callback gas limit is changed
    // @param limit The new Chainlink callback gas limit
    event LinkCallbackGasLimit(uint32 indexed limit);

    /// @notice Emitted when a new admin is added to the contract
    /// @param admin The address of the new admin
    event AdminAdded(address indexed admin);

    /// @notice Emitted when a admin is removed from the contract
    /// @param admin The address of the admin removed
    event AdminRemoved(address indexed admin);

    /// @notice You must be the owner or an admin
    error NotAuthorized();

    /// @notice Initializes the ProbaCompetitionFactory contract
    /// @param _protocol Address of the protocol
    /// @param _protocolFee Protocol fee in basis points
    /// @param _linkToken Address of the LINK token
    /// @param _vrfWrapper Address of the VRFv2 Wrapper
    /// @param _linkFee Link fee amount
    /// @param _linkCallbackGasLimit VRFv2 request callback gas limit
    /// @param _linkRequestConfirmations VRFv2 request confirmations
    constructor(
        address _protocol,
        uint256 _protocolFee,
        address _linkToken,
        address _vrfWrapper,
        uint256 _linkFee,
        uint32 _linkCallbackGasLimit,
        uint16 _linkRequestConfirmations
    ) Ownable(msg.sender) {
        protocolAddress = _protocol;
        protocolFee = _protocolFee;
        linkToken = _linkToken;
        vrfWrapper = _vrfWrapper;
        linkFee = _linkFee;
        linkCallbackGasLimit = _linkCallbackGasLimit;
        linkRequestConfirmations = _linkRequestConfirmations;
    }

    /// @notice Only admins can call the function
    modifier onlyAdmin() {
        if (msg.sender != owner() && !admins[msg.sender]) {
            revert NotAuthorized();
        }
        _;
    }

    /// @notice Creates a new Studio Competition Factory
    /// @param name Name of the studio
    /// @param description Description of the studio
    function createStudioFactory(string memory name, string memory description) public {
        StudioCompetitionFactory newStudio = new StudioCompetitionFactory(
            name, address(this), msg.sender
        );

        emit NewStudio(address(newStudio), msg.sender, name, description);
    }

    /// @notice Sets the protocol address for fees to be sent to
    /// @param addr New protocol fee address
    /// @custom:role-only-owner-admin
    function setProtocolFeeAddress(address addr) external onlyAdmin {
        protocolAddress = addr;

        emit ProtocolFeeAddress(addr);
    }

    /// @notice Sets the protocol fee
    /// @param fee New fee in basis points
    /// @custom:role-only-owner-admin
    function setProtocolFee(uint256 fee) external onlyAdmin {
        protocolFee = fee;

        emit ProtocolFee(fee);
    }

    /// @notice Sets the LINK fee
    /// @param fee New LINK fee amount
    /// @custom:role-only-owner-admin
    function setLinkFee(uint256 fee) external onlyAdmin {
        linkFee = fee;

        emit LinkFee(fee);
    }

    /// @notice Sets the Chainlink VRFv2 callback gas limit
    /// @param limit New gas limit amount
    /// @custom:role-only-owner-admin
    function setCallbackGasLimit(uint32 limit) external onlyAdmin {
        linkCallbackGasLimit = limit;

        emit LinkCallbackGasLimit(limit);
    }

    /// @notice Adds an admin to the contract
    /// @param admin Address of the admin to be added
    /// @custom:role-only-owner
    function addAdmin(address admin) external onlyOwner {
        admins[admin] = true;

        emit AdminAdded(admin);
    }

    /// @notice Removes an admin from the contract
    /// @param admin Address of the admin to be removed
    /// @custom:role-only-owner
    function removeAdmin(address admin) external onlyOwner {
        delete admins[admin];

        emit AdminRemoved(admin);
    }
}
