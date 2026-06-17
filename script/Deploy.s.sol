// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {RashidAward} from "../Contracts/guardian-angel.io.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(1));
        
        address guardian = address(0xB);
        address verifier = address(0xC);
        address offsetRecipient = address(0xD);
        uint256 initialOffsetBps = 500;

        vm.startBroadcast(deployerPrivateKey);

        new RashidAward(
            guardian,
            verifier,
            offsetRecipient,
            initialOffsetBps
        );

        vm.stopBroadcast();
    }
}
