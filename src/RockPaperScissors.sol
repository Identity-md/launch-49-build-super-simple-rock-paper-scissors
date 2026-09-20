// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Two named players, no money, one commit/reveal round per game.
contract RockPaperScissors {
    uint256 public constant REVEAL_WINDOW = 1 days;

    enum Outcome {
        Pending,
        Draw,
        Player1,
        Player2
    }

    struct Game {
        address player1;
        address player2;
        bytes32 commitment1;
        bytes32 commitment2;
        uint256 revealDeadline;
        uint8 move1;
        uint8 move2;
        bool revealed1;
        bool revealed2;
        Outcome outcome;
    }

    uint256 public gameCount;
    mapping(uint256 => Game) public games;

    error InvalidOpponent();
    error UnknownGame();
    error NotPlayer();
    error AlreadySettled();
    error EmptyCommitment();
    error AlreadyCommitted();
    error CopiedCommitment();
    error NotReady();
    error DeadlinePassed();
    error DeadlineNotReached();
    error AlreadyRevealed();
    error InvalidMove();
    error InvalidReveal();

    event Created(uint256 indexed gameId, address indexed player1, address indexed player2);
    event Committed(uint256 indexed gameId, address indexed player, bytes32 commitment);
    event Revealed(uint256 indexed gameId, address indexed player, uint8 move);
    /// @dev timedOut distinguishes a deadline settlement from two valid reveals.
    event Settled(uint256 indexed gameId, Outcome outcome, address winner, bool timedOut);

    function createGame(address opponent) external returns (uint256 gameId) {
        if (opponent == address(0) || opponent == msg.sender) revert InvalidOpponent();
        gameId = ++gameCount;
        Game storage g = games[gameId];
        g.player1 = msg.sender;
        g.player2 = opponent;
        emit Created(gameId, msg.sender, opponent);
    }

    /// @notice Commit keccak256(abi.encode(uint8(move), bytes32(salt))). Moves: 0 rock, 1 paper, 2 scissors.
    function commit(uint256 gameId, bytes32 commitment) external {
        Game storage g = _activeGame(gameId);
        bool first = _isFirst(g);
        if (commitment == bytes32(0)) revert EmptyCommitment();
        if (commitment == (first ? g.commitment2 : g.commitment1)) revert CopiedCommitment();
        if (first) {
            if (g.commitment1 != bytes32(0)) revert AlreadyCommitted();
            g.commitment1 = commitment;
        } else {
            if (g.commitment2 != bytes32(0)) revert AlreadyCommitted();
            g.commitment2 = commitment;
        }
        if (g.commitment1 != bytes32(0) && g.commitment2 != bytes32(0)) {
            g.revealDeadline = block.timestamp + REVEAL_WINDOW;
        }
        emit Committed(gameId, msg.sender, commitment);
    }

    function reveal(uint256 gameId, uint8 move, bytes32 salt) external {
        Game storage g = _activeGame(gameId);
        bool first = _isFirst(g);
        if (g.revealDeadline == 0) revert NotReady();
        if (block.timestamp >= g.revealDeadline) revert DeadlinePassed();
        if (first ? g.revealed1 : g.revealed2) revert AlreadyRevealed();
        if (move > 2) revert InvalidMove();
        if (keccak256(abi.encode(move, salt)) != (first ? g.commitment1 : g.commitment2)) {
            revert InvalidReveal();
        }
        if (first) {
            g.move1 = move;
            g.revealed1 = true;
        } else {
            g.move2 = move;
            g.revealed2 = true;
        }
        emit Revealed(gameId, msg.sender, move);
        if (g.revealed1 && g.revealed2) {
            Outcome outcome = g.move1 == g.move2
                ? Outcome.Draw
                : ((uint256(g.move1) + 2) % 3 == g.move2 ? Outcome.Player1 : Outcome.Player2);
            _settle(gameId, g, outcome, false);
        }
    }

    /// @notice Anyone can finalize at/after the deadline. No reveals is a draw.
    function settleExpired(uint256 gameId) external {
        Game storage g = _activeGame(gameId);
        if (g.revealDeadline == 0) revert NotReady();
        if (block.timestamp < g.revealDeadline) revert DeadlineNotReached();
        Outcome outcome = g.revealed1 ? Outcome.Player1 : (g.revealed2 ? Outcome.Player2 : Outcome.Draw);
        _settle(gameId, g, outcome, true);
    }

    function getGame(uint256 gameId) external view returns (Game memory) {
        if (games[gameId].player1 == address(0)) revert UnknownGame();
        return games[gameId];
    }

    function _activeGame(uint256 gameId) private view returns (Game storage g) {
        g = games[gameId];
        if (g.player1 == address(0)) revert UnknownGame();
        if (g.outcome != Outcome.Pending) revert AlreadySettled();
    }

    function _isFirst(Game storage g) private view returns (bool) {
        if (msg.sender == g.player1) return true;
        if (msg.sender != g.player2) revert NotPlayer();
        return false;
    }

    function _settle(uint256 gameId, Game storage g, Outcome outcome, bool timedOut) private {
        g.outcome = outcome;
        address winner = outcome == Outcome.Player1 ? g.player1 : (outcome == Outcome.Player2 ? g.player2 : address(0));
        emit Settled(gameId, outcome, winner, timedOut);
    }
}
