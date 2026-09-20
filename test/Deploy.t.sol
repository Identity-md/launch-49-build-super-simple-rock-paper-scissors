// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {RockPaperScissors as RPS} from "../src/RockPaperScissors.sol";
import {Deploy} from "../script/Deploy.s.sol";

interface DeployTestVm {
    function setEnv(string calldata name, string calldata value) external;
    function chainId(uint256) external;
    function expectRevert(bytes calldata reason) external;
    function prank(address sender) external;
}

contract DeployTest {
    DeployTestVm private constant vm = DeployTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Foundry's process environment is shared across parallel tests. Keep every
    // environment mutation and script invocation in one sequential test.
    function testDeploymentIntegrationAndChainConfiguration() public {
        vm.setEnv("EXPECTED_CHAIN_ID", "0");
        deploymentReturnsStandaloneGameAndPlaysRound();
        configuredSepoliaDeployment();
        configuredChainMismatchReverts();
        configuredOtherChainDeployment();
        vm.setEnv("EXPECTED_CHAIN_ID", "0");
        defaultSettingSupportsOtherChainsAndFreshInstances();
    }

    function deploymentReturnsStandaloneGameAndPlaysRound() private {
        RPS game = new Deploy().run();
        require(keccak256(address(game).code) == keccak256(type(RPS).runtimeCode), "wrong runtime");
        require(game.gameCount() == 0 && address(game).balance == 0, "nonempty deployment");
        require(game.REVEAL_WINDOW() == 1 days, "wrong protocol window");

        // The only deployed contract is the game: there are no inter-contract links.
        // Exercise its returned address to prove deployment yields a usable instance.
        address opponent = address(0xB);
        bytes32 salt1 = keccak256("deployment test player 1");
        bytes32 salt2 = keccak256("deployment test player 2");
        uint256 id = game.createGame(opponent);
        game.commit(id, keccak256(abi.encode(uint8(0), salt1)));
        vm.prank(opponent);
        game.commit(id, keccak256(abi.encode(uint8(2), salt2)));
        RPS.Game memory record = game.getGame(id);
        require(record.player1 == address(this) && record.player2 == opponent, "wrong players");
        require(record.revealDeadline == block.timestamp + game.REVEAL_WINDOW(), "wrong deadline");
        game.reveal(id, 0, salt1);
        vm.prank(opponent);
        game.reveal(id, 2, salt2);
        require(game.getGame(id).outcome == RPS.Outcome.Player1, "round failed");
    }

    function configuredSepoliaDeployment() private {
        vm.setEnv("EXPECTED_CHAIN_ID", "11155111");
        vm.chainId(11155111);
        RPS game = new Deploy().run();
        require(address(game).code.length > 0 && game.gameCount() == 0, "deployment failed");
    }

    function configuredChainMismatchReverts() private {
        vm.setEnv("EXPECTED_CHAIN_ID", "11155111");
        vm.chainId(31337);
        Deploy deploy = new Deploy();
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnexpectedChain.selector, 11155111, 31337));
        deploy.run();
    }

    function configuredOtherChainDeployment() private {
        vm.setEnv("EXPECTED_CHAIN_ID", "12345");
        vm.chainId(12345);
        require(address(new Deploy().run()).code.length > 0, "hardcoded chain restriction");
    }

    function defaultSettingSupportsOtherChainsAndFreshInstances() private {
        vm.chainId(12345);
        Deploy deploy = new Deploy();
        RPS first = deploy.run();
        first.createGame(address(0xB));
        RPS second = deploy.run();
        require(address(first) != address(second), "reused instance");
        require(first.gameCount() == 1 && second.gameCount() == 0, "shared state");
    }
}
