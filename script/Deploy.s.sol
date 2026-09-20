// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {RockPaperScissors} from "../src/RockPaperScissors.sol";

interface BroadcastVm {
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract Deploy {
    BroadcastVm private constant VM = BroadcastVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (RockPaperScissors deployed) {
        require(block.chainid == 31337 || block.chainid == 11155111, "Use local simulation or Sepolia");
        VM.startBroadcast();
        deployed = new RockPaperScissors();
        VM.stopBroadcast();
    }
}
