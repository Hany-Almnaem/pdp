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
    uint256 public proofSetId;
    uint256 public leafCount;
    uint256 public seed;
    uint256 public challengeCount;

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
        proofSetId = 1;
        leafCount = 100;
        seed = 12345;
        challengeCount = 5;
    }

    function testPosessionProvenOnTime() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.posessionProven(proofSetId, leafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        pdpService.nextProvingPeriod(proofSetId, leafCount);
        vm.roll(block.number + 1);
        pdpService.posessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testNextProvingPeriodCalledLastMinuteOK() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.posessionProven(proofSetId, leafCount, seed, challengeCount);

        // wait until almost the end of proving period 2 
        // this should all work fine
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, leafCount);
        pdpService.posessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testFirstEpochLateToProve() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        vm.expectRevert("Current proving period passed. Open a new proving period.");
        pdpService.posessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testNextProvingPeriodTwiceFails() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);
        pdpService.posessionProven(proofSetId, leafCount, seed, challengeCount);
        uint256 deadline1 = pdpService.provingDeadlines(proofSetId);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        assertEq(pdpService.provingDeadlines(proofSetId), deadline1, "Proving deadline should not change until nextProvingPeriod.");
        pdpService.nextProvingPeriod(proofSetId, leafCount);
        assertEq(pdpService.provingDeadlines(proofSetId), deadline1 + pdpService.getMaxProvingPeriod(), "Proving deadline should be updated");
        assertFalse(pdpService.provenThisPeriod(proofSetId));

        vm.expectRevert("One call to nextProvingPeriod allowed per proving period");
        pdpService.nextProvingPeriod(proofSetId, leafCount); 
    }

    function testFaultWithinOpenPeriod() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        
        // Move to open proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);
        
        // Expect fault event when calling nextProvingPeriod without proof
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(1);
        pdpService.nextProvingPeriod(proofSetId, leafCount);
    }

    function testFaultAfterPeriodOver() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        
        // Move past proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        
        // Expect fault event when calling nextProvingPeriod without proof
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(1);
        pdpService.nextProvingPeriod(proofSetId, leafCount);
    }

    function testNextProvingPeriodWithoutProof() public {
        // Set up the proving deadline without marking as proven
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        // Move to the next period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        // Expect a fault event
        vm.expectEmit();
        emit SimplePDPService.FaultRecord(1);
        pdpService.nextProvingPeriod(proofSetId, leafCount);
        assertFalse(pdpService.provenThisPeriod(proofSetId));
    }

    function testInvalidChallengeCount() public {
        uint256 invalidChallengeCount = 4; // Less than required

        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        vm.expectRevert("Invalid challenge count < 5");
        pdpService.posessionProven(proofSetId, leafCount, seed, invalidChallengeCount);
    }

    function testMultiplePeriodsLate() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);
        // unable to prove possession
        vm.expectRevert("Current proving period passed. Open a new proving period.");
        pdpService.posessionProven(proofSetId, leafCount, seed, challengeCount);

        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(3);
        pdpService.nextProvingPeriod(proofSetId, leafCount);
    }

    function testMultiplePeriodsLateWithInitialProof() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        
        // Move to first open proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);
        
        // Submit valid proof in first period
        pdpService.posessionProven(proofSetId, leafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);

        // Should emit fault record for 2 periods (current period not counted since not yet expired)
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(2);
        pdpService.nextProvingPeriod(proofSetId, leafCount);
    }

    function testCanOnlyProveOncePerPeriod() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        // We're technically at the previous deadline so we fail to prove until we roll forward 1
        vm.expectRevert("Too early. Wait for proving period to open");
        pdpService.posessionProven(proofSetId, leafCount, seed, 5);
        vm.roll(block.number + 1);
        pdpService.posessionProven(proofSetId, leafCount, seed, 5);
        vm.expectRevert("Only one proof of possession allowed per proving period. Open a new proving period.");
        pdpService.posessionProven(proofSetId, leafCount, seed, 5);
    }  

    function testCantProveBeforePeriodIsOpen() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0));
        vm.roll(block.number + pdpService.getMaxProvingPeriod() -100);
        pdpService.posessionProven(proofSetId, leafCount, seed, 5);
        pdpService.nextProvingPeriod(proofSetId, leafCount);
        vm.expectRevert("Too early. Wait for proving period to open");
        pdpService.posessionProven(proofSetId, leafCount, seed, 5);
    }
}
