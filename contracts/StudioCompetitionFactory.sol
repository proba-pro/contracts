// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ProbaCompetitionFactory.sol";
import "./Competition.sol";

/// @notice Factory contract for creating Competition contracts within a studio
contract StudioCompetitionFactory is Ownable {
    /// @notice Name of the Studio Factory
    string private name;

    /// @notice Proba main competition factory, used to fetch
    ///         Chainlink Link Token address and VRF Coordinator address
    ProbaCompetitionFactory public immutable mainFactory;

    /// @notice Emitted when a new competition is started
    /// @param competition The address of the created competition contract
    /// @param name Name of competition
    /// @param description Description of competition
    event NewCompetition(address indexed competition, string name, string description);

    /// @notice Initializes the StudioCompetition contract
    /// @param _name Name of the Studio
    /// @param _factory Address of the ProbaCompetition protocol
    /// @param owner The owner address of the Studio factory contract
    constructor(string memory _name, address _factory, address owner) Ownable(owner) {
        name = _name;
        mainFactory = ProbaCompetitionFactory(_factory);
    }

    /// @notice Creates a new Competition contract, emits address via NewCompetition
    /// @param description The information about the competition
    /// @param rxNFT Symbol of the competition token
    /// @param payment Struct containing payment details about the competition
    /// @param reward Struct containing reward details about the competition
    /// @param limits Struct containing limit details about the competition
    /// @param durationSeconds The duration of the competition in seconds
    function createCompetition(
        string memory description,
        Competition.RxNFT memory rxNFT,
        Competition.Payment memory payment,
        Competition.Reward memory reward,
        Competition.Limits memory limits,
        uint64 durationSeconds
    ) external {
        // Retrieve Chainlink VRFv2 Wrapper and Link Token address
        // from mainFactory to initialize Competition VRFV2WrapperConsumerBase
        address vrfWrapper = mainFactory.vrfWrapper();
        address linkToken = mainFactory.linkToken();

        Competition newCompetition = new Competition(
            address(mainFactory),
            address(this),
            description,
            rxNFT,
            payment,
            reward,
            limits,
            durationSeconds,
            linkToken,
            vrfWrapper
        );

        emit NewCompetition(address(newCompetition), rxNFT.name, description);
    }
}
