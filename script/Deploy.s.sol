// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {RashidAward} from "../Contracts/guardian-angel.io.sol";

/**
 * @title DeployRashidAward
 * @author ELGHALY COMPANY — Sustainable Web3 Division
 * @notice Production-grade deployment framework for the RashidAward protocol.
 * @dev Dynamic environment handling, pre-flight checks, and immutable governance initialization.
 */
contract DeployRashidAward is Script {
    
    function run() external returns (RashidAward awardContract) {
        // 1. Fetch deployment account configurations safely
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_OWNER");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // 2. Fetch operational network parameters with secure default fallback configurations
        address guardian = vm.envOr("PRIVATE_KEY_GUARDIAN", address(0x1111111111111111111111111111111111111111));
        address verifier = vm.envOr("PRIVATE_KEY_VERIFIER", address(0x2222222222222222222222222222222222222222));
        address offsetRecipient = vm.envOr("OFFSET_RECIPIENT_ADDRESS", address(0x3333333333333333333333333333333333333333));
        uint256 offsetBps = vm.envOr("OFFSET_BPS", uint256(500)); // Standard default: 5.00%

        // 3. Pre-Flight Validation Logs & Infrastructure Auditing
        console2.log("====================================================");
        console2.log("GUARDIAN ANGEL PROTOCOL - ENTERPRISE LAUNCH SYSTEM");
        console2.log("====================================================");
        console2.log("Deployer Address:    ", deployerAddress);
        console2.log("Deployer Balance:    ", deployerAddress.balance);
        console2.log("Target Guardian:     ", guardian);
        console2.log("Target Verifier:     ", verifier);
        console2.log("Offset Recipient:    ", offsetRecipient);
        console2.log("Carbon Offset BPS:   ", offsetBps);
        console2.log("====================================================");

        // Assert contract funding availability before initiating state transmission
        if (deployerAddress.balance == 0) {
            console2.log("[CRITICAL ERROR] Deployer address has zero balance. Refusing execution.");
            revert("INSUFFICIENT_DEPLOYMENT_GAS");
        }

        // 4. Execution & Mainnet/Testnet Broadcast Layer
        console2.log("[SYSTEM] Broadcasting on-chain deployment transactions...");
        vm.startBroadcast(deployerPrivateKey);

        awardContract = new RashidAward(
            guardian,
            verifier,
            offsetRecipient,
            offsetBps
        );

        vm.stopBroadcast();

        // 5. Post-Deployment Integrity Records
        console2.log("====================================================");
        console2.log("[SUCCESS] Core Protocol Orchestration Finalized.");
        console2.log("Contract Address:    ", address(awardContract));
        console2.log("Protocol Owner:      ", awardContract.owner());
        console2.log("EIP-712 Separator:   ");
        console2.logBytes32(awardContract.domainSeparator());
        console2.log("====================================================");

        return awardContract;
    }
}
