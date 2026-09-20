// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {RockPaperScissors as RPS} from "../src/RockPaperScissors.sol";

interface TestVm {
    function prank(address) external;
    function warp(uint256) external;
    function expectRevert(bytes4) external;
    function expectRevert(bytes calldata) external;
    function expectEmit(bool, bool, bool, bool, address) external;
    function deal(address, uint256) external;
}

contract RockPaperScissorsTest {
    TestVm private constant vm = TestVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant ALICE = address(0xA);
    address private constant BOB = address(0xB);
    address private constant EVE = address(0xE);
    bytes32 private constant SALT_A = keccak256("test salt A");
    bytes32 private constant SALT_B = keccak256("test salt B");
    RPS private game;
    uint256 private id;

    event Created(uint256 indexed gameId, address indexed player1, address indexed player2);
    event Committed(uint256 indexed gameId, address indexed player, bytes32 commitment);
    event Revealed(uint256 indexed gameId, address indexed player, uint8 move);
    event Settled(uint256 indexed gameId, RPS.Outcome outcome, address winner, bool timedOut);

    function setUp() public {
        vm.warp(100);
        game = new RPS();
        vm.prank(ALICE);
        id = game.createGame(BOB);
    }

    function hash(uint8 move, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encode(move, salt));
    }

    function commitBoth(uint8 a, uint8 b) private {
        vm.prank(ALICE);
        game.commit(id, hash(a, SALT_A));
        vm.prank(BOB);
        game.commit(id, hash(b, SALT_B));
    }

    function revealAs(address player, uint8 move, bytes32 salt) private {
        vm.prank(player);
        game.reveal(id, move, salt);
    }

    function assertOutcome(RPS.Outcome expected) private view {
        require(game.getGame(id).outcome == expected, "wrong outcome");
    }

    function testAllNineOutcomesBothRevealOrders() public {
        for (uint8 a; a < 3; a++) {
            for (uint8 b; b < 3; b++) {
                for (uint8 order; order < 2; order++) {
                    vm.prank(ALICE);
                    id = game.createGame(BOB);
                    commitBoth(a, b);
                    if (order == 0) {
                        revealAs(ALICE, a, SALT_A);
                        assertOutcome(RPS.Outcome.Pending);
                        revealAs(BOB, b, SALT_B);
                    } else {
                        revealAs(BOB, b, SALT_B);
                        assertOutcome(RPS.Outcome.Pending);
                        revealAs(ALICE, a, SALT_A);
                    }
                    // Explicit independent truth table, rather than production modulo logic.
                    bool aliceWins = (a == 0 && b == 2) || (a == 1 && b == 0) || (a == 2 && b == 1);
                    assertOutcome(a == b ? RPS.Outcome.Draw : (aliceWins ? RPS.Outcome.Player1 : RPS.Outcome.Player2));
                    RPS.Game memory g = game.getGame(id);
                    require(g.revealed1 && g.revealed2 && g.move1 == a && g.move2 == b, "record");
                }
            }
        }
    }

    function testFuzzValidReveal(uint8 a, uint8 b, bytes32 saltA, bytes32 saltB, bool reverse) public {
        a %= 3;
        b %= 3;
        if (a == b && saltA == saltB) saltB = bytes32(uint256(saltB) ^ 1);
        vm.prank(ALICE);
        game.commit(id, hash(a, saltA));
        vm.prank(BOB);
        game.commit(id, hash(b, saltB));
        revealAs(reverse ? BOB : ALICE, reverse ? b : a, reverse ? saltB : saltA);
        revealAs(reverse ? ALICE : BOB, reverse ? a : b, reverse ? saltA : saltB);
        bool aliceWins = (a == 0 && b == 2) || (a == 1 && b == 0) || (a == 2 && b == 1);
        assertOutcome(a == b ? RPS.Outcome.Draw : (aliceWins ? RPS.Outcome.Player1 : RPS.Outcome.Player2));
    }

    function testForfeitAliceAtDeadline() public {
        commitBoth(0, 1);
        revealAs(ALICE, 0, SALT_A);
        vm.warp(game.getGame(id).revealDeadline);
        vm.expectEmit(true, false, false, true, address(game));
        emit Settled(id, RPS.Outcome.Player1, ALICE, true);
        vm.prank(EVE);
        game.settleExpired(id);
        assertOutcome(RPS.Outcome.Player1);
    }

    function testForfeitBobAfterDeadline() public {
        commitBoth(1, 0);
        revealAs(BOB, 0, SALT_B);
        vm.warp(game.getGame(id).revealDeadline + 30 days);
        game.settleExpired(id);
        assertOutcome(RPS.Outcome.Player2);
    }

    function testNeitherRevealsDraw() public {
        commitBoth(0, 2);
        vm.warp(game.getGame(id).revealDeadline);
        vm.expectEmit(true, false, false, true, address(game));
        emit Settled(id, RPS.Outcome.Draw, address(0), true);
        game.settleExpired(id);
        assertOutcome(RPS.Outcome.Draw);
    }

    function testDeadlineStartsOnlyWithSecondCommitInEitherOrder() public {
        vm.prank(BOB);
        game.commit(id, hash(2, SALT_B));
        require(game.getGame(id).revealDeadline == 0, "early deadline");
        vm.warp(100 days);
        vm.expectRevert(RPS.NotReady.selector);
        game.settleExpired(id);
        vm.prank(ALICE);
        game.commit(id, hash(0, SALT_A));
        require(game.getGame(id).revealDeadline == 101 days, "deadline");
        revealAs(BOB, 2, SALT_B);
        require(game.getGame(id).revealDeadline == 101 days, "extended deadline");
    }

    function testOneSecondBeforeDeadlineCanRevealButCannotExpire() public {
        commitBoth(0, 2);
        vm.warp(game.getGame(id).revealDeadline - 1);
        vm.expectRevert(RPS.DeadlineNotReached.selector);
        game.settleExpired(id);
        revealAs(ALICE, 0, SALT_A);
        revealAs(BOB, 2, SALT_B);
        assertOutcome(RPS.Outcome.Player1);
    }

    function testRevealAtOrAfterDeadlineRejected() public {
        commitBoth(0, 2);
        uint256 deadline = game.getGame(id).revealDeadline;
        vm.warp(deadline);
        vm.expectRevert(RPS.DeadlinePassed.selector);
        revealAs(ALICE, 0, SALT_A);
        vm.warp(deadline + 1);
        vm.expectRevert(RPS.DeadlinePassed.selector);
        revealAs(BOB, 2, SALT_B);
        require(!game.getGame(id).revealed1 && !game.getGame(id).revealed2, "late reveal stored");
    }

    function testInvalidOpponents() public {
        vm.expectRevert(RPS.InvalidOpponent.selector);
        game.createGame(address(0));
        vm.prank(ALICE);
        vm.expectRevert(RPS.InvalidOpponent.selector);
        game.createGame(ALICE);
        require(game.gameCount() == 1, "count changed");
    }

    function testUnknownGames() public {
        vm.expectRevert(RPS.UnknownGame.selector);
        game.commit(0, SALT_A);
        vm.expectRevert(RPS.UnknownGame.selector);
        game.reveal(2, 0, SALT_A);
        vm.expectRevert(RPS.UnknownGame.selector);
        game.settleExpired(2);
        vm.expectRevert(RPS.UnknownGame.selector);
        game.getGame(2);
    }

    function testNonPlayersCannotCommitOrReveal() public {
        vm.prank(EVE);
        vm.expectRevert(RPS.NotPlayer.selector);
        game.commit(id, SALT_A);
        commitBoth(0, 1);
        vm.prank(EVE);
        vm.expectRevert(RPS.NotPlayer.selector);
        game.reveal(id, 0, SALT_A);
    }

    function testCopiedCommitmentRejectedInEitherOrder() public {
        for (uint8 order; order < 2; order++) {
            vm.prank(ALICE);
            id = game.createGame(BOB);
            address first = order == 0 ? ALICE : BOB;
            address second = order == 0 ? BOB : ALICE;
            vm.prank(first);
            game.commit(id, hash(0, SALT_A));
            vm.prank(second);
            vm.expectRevert(RPS.CopiedCommitment.selector);
            game.commit(id, hash(0, SALT_A));
            require(game.getGame(id).revealDeadline == 0, "copy started reveal");
            vm.prank(second);
            game.commit(id, hash(0, SALT_B));
            revealAs(first, 0, SALT_A);
            revealAs(second, 0, SALT_B);
            assertOutcome(RPS.Outcome.Draw);
        }
    }

    function testZeroAndDuplicateCommitments() public {
        vm.prank(ALICE);
        vm.expectRevert(RPS.EmptyCommitment.selector);
        game.commit(id, bytes32(0));
        commitBoth(0, 1);
        vm.prank(ALICE);
        vm.expectRevert(RPS.AlreadyCommitted.selector);
        game.commit(id, SALT_A);
        vm.prank(BOB);
        vm.expectRevert(RPS.AlreadyCommitted.selector);
        game.commit(id, SALT_B);
        require(game.getGame(id).commitment1 == hash(0, SALT_A), "commit changed");
    }

    function testNotReadyWithoutBothCommitments() public {
        vm.expectRevert(RPS.NotReady.selector);
        revealAs(ALICE, 0, SALT_A);
        vm.expectRevert(RPS.NotReady.selector);
        game.settleExpired(id);
        vm.prank(ALICE);
        game.commit(id, hash(0, SALT_A));
        vm.expectRevert(RPS.NotReady.selector);
        revealAs(ALICE, 0, SALT_A);
        vm.expectRevert(RPS.NotReady.selector);
        revealAs(BOB, 0, SALT_B);
    }

    function testWrongMoveSaltAndPackedEncodingThenRecovery() public {
        commitBoth(0, 2);
        vm.expectRevert(RPS.InvalidReveal.selector);
        revealAs(ALICE, 1, SALT_A);
        vm.expectRevert(RPS.InvalidReveal.selector);
        revealAs(ALICE, 0, SALT_B);
        require(!game.getGame(id).revealed1, "failed reveal stored");
        revealAs(ALICE, 0, SALT_A);
        revealAs(BOB, 2, SALT_B);
        assertOutcome(RPS.Outcome.Player1);
        vm.prank(ALICE);
        id = game.createGame(BOB);
        vm.prank(ALICE);
        game.commit(id, keccak256(abi.encodePacked(uint8(0), SALT_A)));
        vm.prank(BOB);
        game.commit(id, hash(2, SALT_B));
        vm.expectRevert(RPS.InvalidReveal.selector);
        revealAs(ALICE, 0, SALT_A);
    }

    function testFuzzInvalidMoveEvenWithMatchingCommitment(uint8 invalid) public {
        if (invalid < 3) invalid = 3;
        commitBoth(invalid, invalid);
        vm.expectRevert(RPS.InvalidMove.selector);
        revealAs(ALICE, invalid, SALT_A);
        vm.expectRevert(RPS.InvalidMove.selector);
        revealAs(BOB, invalid, SALT_B);
    }

    function testDuplicateRevealBothPlayers() public {
        commitBoth(0, 2);
        revealAs(ALICE, 0, SALT_A);
        vm.expectRevert(RPS.AlreadyRevealed.selector);
        revealAs(ALICE, 0, SALT_A);
        vm.prank(ALICE);
        id = game.createGame(BOB);
        commitBoth(0, 2);
        revealAs(BOB, 2, SALT_B);
        vm.expectRevert(RPS.AlreadyRevealed.selector);
        revealAs(BOB, 2, SALT_B);
    }

    function testSettledGamesImmutableNormalAndTimeout() public {
        for (uint8 mode; mode < 2; mode++) {
            vm.prank(ALICE);
            id = game.createGame(BOB);
            commitBoth(0, 2);
            revealAs(ALICE, 0, SALT_A);
            if (mode == 0) {
                revealAs(BOB, 2, SALT_B);
            } else {
                vm.warp(game.getGame(id).revealDeadline);
                game.settleExpired(id);
            }
            bytes32 beforeHash = keccak256(abi.encode(game.getGame(id)));
            vm.expectRevert(RPS.AlreadySettled.selector);
            game.settleExpired(id);
            vm.expectRevert(RPS.AlreadySettled.selector);
            revealAs(BOB, 2, SALT_B);
            vm.prank(ALICE);
            vm.expectRevert(RPS.AlreadySettled.selector);
            game.commit(id, SALT_A);
            require(keccak256(abi.encode(game.getGame(id))) == beforeHash, "settled state mutated");
        }
    }

    function testIndependentGamesAndPublicRecord() public {
        commitBoth(0, 2);
        vm.prank(BOB);
        uint256 other = game.createGame(EVE);
        vm.prank(EVE);
        game.commit(other, hash(1, SALT_B));
        revealAs(ALICE, 0, SALT_A);
        revealAs(BOB, 2, SALT_B);
        RPS.Game memory g = game.getGame(other);
        require(other == 2 && game.gameCount() == 2, "ids");
        require(g.player1 == BOB && g.player2 == EVE && g.revealDeadline == 0, "other changed");
        require(g.outcome == RPS.Outcome.Pending && g.commitment2 == hash(1, SALT_B), "other record");
        (address player1, address player2,,,,,,,,) = game.games(id);
        require(player1 == ALICE && player2 == BOB, "public getter");
    }

    function testLifecycleEvents() public {
        vm.expectEmit(true, true, true, true, address(game));
        emit Created(2, ALICE, BOB);
        vm.prank(ALICE);
        id = game.createGame(BOB);
        vm.expectEmit(true, true, false, true, address(game));
        emit Committed(id, ALICE, hash(1, SALT_A));
        vm.prank(ALICE);
        game.commit(id, hash(1, SALT_A));
        vm.expectEmit(true, true, false, true, address(game));
        emit Committed(id, BOB, hash(0, SALT_B));
        vm.prank(BOB);
        game.commit(id, hash(0, SALT_B));
        vm.expectEmit(true, true, false, true, address(game));
        emit Revealed(id, BOB, 0);
        revealAs(BOB, 0, SALT_B);
        vm.expectEmit(true, true, false, true, address(game));
        emit Revealed(id, ALICE, 1);
        vm.expectEmit(true, false, false, true, address(game));
        emit Settled(id, RPS.Outcome.Player1, ALICE, false);
        revealAs(ALICE, 1, SALT_A);
    }

    function testRejectsEther() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(game).call{value: 1}("");
        require(!success && address(game).balance == 0, "accepted ether");
        (success,) = address(game).call{value: 1}(abi.encodeCall(game.createGame, (BOB)));
        require(!success && game.gameCount() == 1, "payable game");
    }
}
