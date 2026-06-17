// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {RashidAward} from "../src/guardian-angel.io.sol";

contract RashidAwardTest is Test {
    RashidAward public awardContract;

    // Standardized cryptographic test actors
    address public owner = address(0xA);
    address public guardian = address(0xB);
    address public verifier = address(0xC);
    address public offsetRecipient = address(0xD);
    address public recipient = address(0xE);

    uint256 public initialOffsetBps = 500; // 5%

    function setUp() public {
        // Deploy the system within a controlled test environment
        vm.startPrank(owner);
        awardContract = new RashidAward(
            guardian,
            verifier,
            offsetRecipient,
            initialOffsetBps
        );
        vm.stopPrank();
        
        // Provision the contract with initial capital liquidity for distribution testing
        vm.deal(address(awardContract), 100 ether);
    }

    function test_ConstructorInitialization() public view {
        assertEq(awardContract.owner(), owner);
        assertEq(awardContract.guardian(), guardian);
        assertEq(awardContract.verifier(), verifier);
        assertEq(awardContract.offsetRecipient(), offsetRecipient);
        assertEq(awardContract.offsetBps(), initialOffsetBps);
    }

    function test_CreateAward_Success() public {
        vm.prank(guardian);
        awardContract.createAward(recipient, 1 ether);

        (address rec, uint256 amt, bool verified, bool distributed, ) = awardContract.awards(0);
        assertEq(rec, recipient);
        assertEq(amt, 1 ether);
        assertFalse(verified);
        assertFalse(distributed);
    }

    function test_CreateAward_RevertIfNotGuardian() public {
        vm.expectRevert(RashidAward.NotGuardian.selector);
        vm.prank(owner);
        awardContract.createAward(recipient, 1 ether);
    }

    function test_VerifyAward_Success() public {
        vm.prank(guardian);
        awardContract.createAward(recipient, 1 ether);

        vm.prank(verifier);
        awardContract.verifyAward(0);

        (, , bool verified, , ) = awardContract.awards(0);
        assertTrue(verified);
    }

    function test_DistributeAward_SuccessWithCarbonOffset() public {
        vm.prank(guardian);
        awardContract.createAward(recipient, 10 ether);

        vm.prank(verifier);
        awardContract.verifyAward(0);

        uint256 initialRecipientBalance = recipient.balance;
        uint256 initialOffsetBalance = offsetRecipient.balance;

        // Payout distribution triggered externally
        awardContract.distributeAward(0);

        uint256 expectedOffset = (10 ether * initialOffsetBps) / 10000;
        uint256 expectedRecipientAmt = 10 ether - expectedOffset;

        assertEq(recipient.balance - initialRecipientBalance, expectedRecipientAmt);
        assertEq(offsetRecipient.balance - initialOffsetBalance, expectedOffset);

        (, , , bool distributed, ) = awardContract.awards(0);
        assertTrue(distributed);
    }

    function test_ProposalSystem_EnforcesMultiSigAndTimelock() public {
        bytes32 paramHash = keccak256("offsetBps");
        uint256 newValue = 1000; // Update configuration to 10%

        uint256 currentTimestamp = block.timestamp;
        bytes32 proposalId = keccak256(abi.encodePacked(paramHash, newValue, currentTimestamp));
        
        vm.prank(owner);
        awardContract.proposeChange(paramHash, newValue);

        vm.prank(guardian);
        awardContract.approveProposal(proposalId);

        // Execution should fail immediately due to active security timelock
        vm.expectRevert(RashidAward.TimelockActive.selector);
        vm.prank(owner);
        awardContract.executeProposal(proposalId);

        // Fast-forward the network state time parameters past the 2-day barrier
        vm.warp(block.timestamp + 2 days);

        vm.prank(owner);
        awardContract.executeProposal(proposalId);

        assertEq(awardContract.offsetBps(), newValue);
    }
}
