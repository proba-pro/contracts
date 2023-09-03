// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import { Test } from "forge-std/Test.sol";

import { ProbaCompetitionFactory } from "../contracts/ProbaCompetitionFactory.sol";

contract ProbaCompetitionFactoryTest is Test {
    ProbaCompetitionFactory proba;

    function setUp() public virtual {
        // Goerli setup for VRF v2
        address protocolAddress = address(0x0E5315780d39ce7AA64519Df52Ba1765F2676c8E);
        uint256 protocolFee = 0;
        address linkTokenAddress = address(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
        address vrfWrapper = address(0x708701a1DfF4f478de54383E49a627eD4852C816);
        uint32 callbackGasLimit = 60_000;
        uint16 requestConfirmations = 3;
        uint256 linkFee = 0.5 ether;

        proba = new ProbaCompetitionFactory(
            protocolAddress,
            protocolFee,
            linkTokenAddress,
            vrfWrapper,
            linkFee,
            callbackGasLimit,
            requestConfirmations
        );
    }

    function test_CreateStudioFactory() public {
        string memory name = "NiceStudio";
        string memory description = "A nice studio";
        vm.expectEmit(false, true, true, true);
        emit ProbaCompetitionFactory.NewStudio(address(0), address(this), name, description);
        proba.createStudioFactory(name, description);
    }

    function test_NotOwner() public {
        vm.startPrank(address(1));

        vm.expectRevert();
        proba.addAdmin(address(0));

        vm.expectRevert();
        proba.removeAdmin(address(0));

        vm.stopPrank();
    }

    function test_NotAdmin() public {
        vm.startPrank(address(1));

        vm.expectRevert(ProbaCompetitionFactory.NotAuthorized.selector);
        proba.setProtocolFeeAddress(address(0));

        vm.expectRevert(ProbaCompetitionFactory.NotAuthorized.selector);
        proba.setProtocolFee(0);

        vm.expectRevert(ProbaCompetitionFactory.NotAuthorized.selector);
        proba.setLinkFee(0);

        vm.expectRevert(ProbaCompetitionFactory.NotAuthorized.selector);
        proba.setCallbackGasLimit(0);

        vm.stopPrank();
    }

    function test_OwnerOnly() public {
        address admin = address(1);

        vm.expectEmit(true, true, true, true);
        emit AdminAdded(admin);
        proba.addAdmin(admin);

        vm.expectEmit(true, true, true, true);
        emit AdminRemoved(admin);
        proba.removeAdmin(admin);
    }

    function test_AdminOnly() public {
        address admin = address(1);
        proba.addAdmin(admin);
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeAddress(address(2));
        proba.setProtocolFeeAddress(address(2));
        assertEq(proba.protocolAddress(), address(2));

        vm.expectEmit(true, true, true, true);
        emit ProbaCompetitionFactory.ProtocolFee(100);
        proba.setProtocolFee(100);
        assertEq(proba.protocolFee(), 100);

        vm.expectEmit(true, true, true, true);
        emit ProbaCompetitionFactory.LinkFee(50);
        proba.setLinkFee(50);
        assertEq(proba.linkFee(), 50);

        // these 2 lines seem to trigger a bug in the compiler TODO
        //vm.expectEmit(true, true, true, true);
        //emit ProbaCompetitionFactory.LinkCallbackGasLimit(100);
        proba.setCallbackGasLimit(100);
        assertEq(proba.linkCallbackGasLimit(), 100);

        vm.stopPrank();
    }

    // Solidity/NatSpec bug prevents referring to fully qualified event names e.g.
    // ProbaCompetitionFactory.NewStudio
    event NewStudio(address indexed studioFactory, address indexed creator, string name, string description);
    event ProtocolFee(uint256 indexed fee);
    event ProtocolFeeAddress(address indexed addr);
    event LinkFee(uint256 indexed fee);
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
}
