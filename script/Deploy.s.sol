// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {RockPaperScissors} from "../src/RockPaperScissors.sol";

interface BroadcastVm {
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
    function startBroadcast() external;
    function stopBroadcast() external;
}

contract Deploy {
    BroadcastVm private constant VM = BroadcastVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error UnexpectedChain(uint256 expected, uint256 actual);

    /// @notice EXPECTED_CHAIN_ID defaults to 0 (use the execution chain).
    /// @dev Signer selection belongs to Forge's CLI; no keys are read here.
    function run() external returns (RockPaperScissors deployed) {
        uint256 expectedChainId = VM.envOr("EXPECTED_CHAIN_ID", uint256(0));
        if (expectedChainId != 0 && block.chainid != expectedChainId) {
            revert UnexpectedChain(expectedChainId, block.chainid);
        }
        VM.startBroadcast();
        deployed = new RockPaperScissors();
        VM.stopBroadcast();
    }
}
