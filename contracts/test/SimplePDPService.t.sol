// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPListener, PDPVerifier} from "../src/PDPVerifier.sol";
import {SimplePDPService, PDPRecordKeeper} from "../src/SimplePDPService.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {Cids} from "../src/Cids.sol";


contract SimplePDPServiceTest is Test {
    SimplePDPService public pdpService;
    address public pdpVerifierAddress;

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
    }

    function testInitialState() public view {
        assertEq(pdpService.pdpVerifierAddress(), pdpVerifierAddress, "PDP verifier address should be set correctly");
    }

    function testAddRecord() public {
        uint64 epoch = 100;
        uint256 proofSetId = 1;

        vm.roll(epoch);
        pdpService.proofSetCreated(proofSetId, address(this));
        assertEq(pdpService.getEventCount(proofSetId), 1, "Event count should be 1 after adding a record");

        SimplePDPService.EventRecord memory eventRecord = pdpService.getEvent(proofSetId, 0);

        assertEq(eventRecord.epoch, epoch, "Recorded epoch should match");
        assertEq(uint(eventRecord.operationType), uint(PDPRecordKeeper.OperationType.CREATE), "Recorded operation type should match");
        assertEq(eventRecord.extraData, abi.encode(address(this)), "Recorded extra data should match");
    }

    function testListEvents() public {
        uint256 proofSetId = 1;
        uint64 epoch1 = 100;
        uint64 epoch2 = 200;

        uint256 firstRoot = 42;
        PDPVerifier.RootData[] memory rootData = new PDPVerifier.RootData[](1);
        rootData[0] = PDPVerifier.RootData(Cids.Cid("test cid"), 100);

        vm.roll(epoch1);
        pdpService.proofSetCreated(proofSetId, address(this));
        vm.roll(epoch2);
        pdpService.rootsAdded(proofSetId, firstRoot, rootData);

        SimplePDPService.EventRecord[] memory events = pdpService.listEvents(proofSetId);

        assertEq(events.length, 2, "Should have 2 events");
        assertEq(events[0].epoch, epoch1, "First event epoch should match");
        assertEq(uint(events[0].operationType), uint(PDPRecordKeeper.OperationType.CREATE), "First event operation type should match");
        assertEq(events[0].extraData, abi.encode(address(this)), "First event extra data should match");

        assertEq(events[1].epoch, epoch2, "Second event epoch should match");
        assertEq(uint(events[1].operationType), uint(PDPRecordKeeper.OperationType.ADD), "Second event operation type should match");
        assertEq(events[1].extraData, abi.encode(firstRoot, rootData), "Second event extra data should match");
    }

    function testOnlyPDPVerifierCanAddRecord() public {
        uint256 proofSetId = 1;

        vm.prank(address(0xdead));
        vm.expectRevert("Caller is not the PDP verifier");
        pdpService.proofSetCreated(proofSetId, address(this));
    }

    function testGetEventOutOfBounds() public {
        uint256 proofSetId = 1;
        vm.expectRevert("Event index out of bounds");
        pdpService.getEvent(proofSetId, 0);
    }

    function testGetMaxProvingPeriod() public view {
        uint64 maxPeriod = pdpService.getMaxProvingPeriod();
        assertEq(maxPeriod, 2880, "Max proving period should be 2880");
    }

    function testGetChallengesPerProof() public view{
        uint64 challenges = pdpService.getChallengesPerProof();
        assertEq(challenges, 5, "Challenges per proof should be 5");
    }
}

contract SimplePDPServiceFaultsTest is Test {
    SimplePDPService public pdpService;
    address public pdpVerifierAddress;

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
    }

    function testPosessionProvenOnTime() public {
        uint256 proofSetId = 1;
        uint256 challengedLeafCount = 100;
        uint256 seed = 12345;
        uint256 challengeCount = 5;

        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        // Warp to just before the deadline
        vm.warp(block.number + pdpService.getMaxProvingPeriod() - 1);
        pdpService.posessionProven(proofSetId, challengedLeafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(proofSetId));
    }

    function testPosessionProvenLate() public {
        uint256 proofSetId = 1;
        uint256 challengedLeafCount = 100;
        uint256 seed = 12345;
        uint256 challengeCount = 5;

        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        // Warp to after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        //Expect a LATE fault event
        vm.expectEmit();
        emit SimplePDPService.FaultRecord(SimplePDPService.FaultType.LATE, 1);
        pdpService.posessionProven(proofSetId, challengedLeafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(proofSetId));
    }

    function testNextProvingPeriodWithoutProof() public {
        uint256 proofSetId = 1;
        uint256 leafCount = 100;

        // Set up the proving deadline without marking as proven
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        // Move to the next period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        // Expect a SKIPPED fault event
        vm.expectEmit();
        emit SimplePDPService.FaultRecord(SimplePDPService.FaultType.SKIPPED, 1);
        pdpService.nextProvingPeriod(proofSetId, leafCount);
        assertFalse(pdpService.provenThisPeriod(proofSetId));
    }

    function testInvalidChallengeCount() public {
        uint256 proofSetId = 1;
        uint256 challengedLeafCount = 100;
        uint256 seed = 12345;
        uint256 invalidChallengeCount = 4; // Less than required

        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        vm.expectRevert("Invalid challenge count < 5");
        pdpService.posessionProven(proofSetId, challengedLeafCount, seed, invalidChallengeCount);
    }

    function testMultiplePeriodsLate() public {
        uint256 proofSetId = 1;
        uint256 challengedLeafCount = 100;
        uint256 seed = 12345;
        uint256 challengeCount = 5;

        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);
        // Expect a LATE fault event with 3 periods
        vm.expectEmit();
        emit SimplePDPService.FaultRecord(SimplePDPService.FaultType.LATE, 3);
        pdpService.posessionProven(proofSetId, challengedLeafCount, seed, challengeCount);
    }
}
