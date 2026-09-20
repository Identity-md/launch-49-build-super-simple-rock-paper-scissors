# Rock Paper Scissors

One Solidity contract for two-player, single-round games on Sepolia (chain ID **11155111**). No token, ETH stakes, application fees, owner, admin, proxy, upgrade path, or external calls. Transactions still cost network gas. The constructor has **no arguments**.

## Rules and interface

1. Player 1 calls `createGame(opponent)` with a different, nonzero address. IDs start at 1. Only that creator and the named opponent can play; creating a game does not force the opponent to participate.
2. Each player calls `commit(gameId, commitment)` once. The hash must be nonzero and differ from the other player's hash. Neither player may reveal until both commits exist. The second commit sets `revealDeadline = block.timestamp + 86400` (one day).
3. Each calls `reveal(gameId, move, salt)` strictly **before** the deadline. Moves are `uint8`: **0 rock**, **1 paper**, **2 scissors**. A correct reveal is recorded permanently; the second valid reveal automatically settles the game. Rock beats scissors, scissors beats paper, and paper beats rock. Equal moves draw.
4. **At or after** the deadline, anyone calls `settleExpired(gameId)`. The only player who revealed wins by forfeit, even if their move would otherwise lose. If neither revealed, the result is a draw. Late reveals always revert. Contracts do not execute themselves: a transaction is required to settle a timeout.

`games(id)` exposes the public record; `getGame(id)` returns a named struct and rejects unknown IDs. The record includes both players, hashes, deadline, moves, reveal flags, and outcome (`0 Pending`, `1 Draw`, `2 Player1`, `3 Player2`). Check reveal flags: a default zero move does not mean rock was revealed. State-changing calls reject unknown or settled games. Final records cannot be changed.

Events are `Created(gameId, player1, player2)`, `Committed(gameId, player, commitment)`, `Revealed(gameId, player, move)`, and `Settled(gameId, outcome, winner, timedOut)`. Draws have a zero winner; `timedOut` identifies deadline settlements. The public record retains the reveal deadline and flags as well.

## Computing commitments

Use exactly **`keccak256(abi.encode(uint8(move), bytes32(salt)))`**, a hash of a 64-byte ABI encoding. Do not use `abi.encodePacked`, text concatenation, or NIST SHA3-256. For example, locally with Foundry tools:

```sh
COMMITMENT=$(cast keccak "$(cast abi-encode 'f(uint8,bytes32)' 0 "$SALT")")
```

`SALT` must be a private, cryptographically random 32-byte value (hex encoded), freshly generated for every player and game. Save the move and salt securely until reveal; commitments cannot be replaced and lost salts cannot be recovered. Never publish a salt before both commitments are mined. Test salts in this repository are public and unsuitable for real play.

The mandated hash binds only move and salt, not player, game, chain, or contract. Identical commitments in the same game are rejected to prevent an opponent copying the hash and then copying the revealed preimage to force a draw. An opponent can also front-run a pending commitment with the same hash, causing the original transaction to revert; the original player must then choose a fresh salt and recommit. This does not provide cross-game domain separation: never reuse salts or preimages between games or deployments. Short or predictable salts permit guessing among the three moves. Hashes are not checked for valid preimages until reveal; committing an invalid move results in an inability to reveal and possible forfeit.

There is intentionally **no commit deadline or cancellation**. If either player never commits, the game remains pending forever; no funds are locked, and either player may create another game. A participant may refuse to play or reveal. Named opponents may be contracts unable to use the interface; the creator is responsible for choosing a willing, capable opponent. This is a casual game, not a ranked or anti-Sybil system.

Deadlines use block timestamps and transaction inclusion time, not the time a transaction was submitted. Players should reveal well before the deadline and monitor confirmation/reorganizations. No automated keeper is provided. Ordinary ETH transfers and payable calls revert; forcibly sent ETH cannot be recovered because there are no fund-management functions.

## Offline build, tests, and local deployment simulation

Prerequisites: Foundry (`forge` and optionally `cast`) and standard Solidity compiler **0.8.30** installed in Foundry's compiler cache. No Solidity libraries or third-party dependencies are needed: all contract, script, and minimal cheatcode interfaces are ordinary source files here. Toolchain binaries are environment prerequisites; the project does not download dependencies or execute compiler wrappers. Validation used Forge 1.7.1 and the preinstalled compiler. An offline verifier must provide that toolchain.

```sh
forge build --offline
forge test --offline
forge fmt --check
forge script script/Deploy.s.sol:Deploy --offline --chain 31337
```

The last command executes the actual deployment script in Foundry's local EVM, with no RPC, private key, or broadcast. The returned address is only a simulated address. Tests cover all nine move pairs in both reveal orders, randomized valid reveals and invalid moves, both forfeit winners, no-reveal draws, exact deadline boundaries, invalid salts/encodings, unauthorized and repeated actions, immutable results, independent game records, event payloads, ETH rejection, and deployment chain checks.

Compiler settings: optimizer enabled with 200 runs, EVM target `paris` (supported on Sepolia). FFI and filesystem cheatcode permissions are disabled. Timestamp lint warnings are expected because the timeout deliberately compares block timestamps.

## Sepolia deployment — operator only

Contributors only build, test, and simulate. They **never broadcast and never receive keys**. A separately authorized deployment operator maintains their own Sepolia-funded signing account, imports it into their own encrypted Foundry keystore as `sepolia-deployer`, and supplies their own trusted RPC endpoint. No wallet or endpoint is included in this project. Do not send private keys to contributors, put them in this repository, or put them in command-line arguments.

On the operator's machine, set `SEPOLIA_RPC_URL` to the Sepolia RPC endpoint and `DEPLOYER_ADDRESS` to the address for that keystore account. After reviewing the source and passing the offline checks, the **exact broadcast command** is:

```sh
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --chain 11155111 \
  --account sepolia-deployer \
  --sender "$DEPLOYER_ADDRESS" \
  --broadcast
```

The script uses `startBroadcast()` with the operator-selected signer, creates one `RockPaperScissors` with no constructor arguments, and calls `stopBroadcast()`. Its chain guard permits only local chain 31337 and Sepolia 11155111. The operator must check the RPC network, command, transaction preview, and account before signing. Run the same command without `--broadcast` for an RPC-backed simulation first. There is no ETH deployment value or post-deployment admin configuration; only gas is funded. The fixed reveal window cannot be changed after deployment.

The operator is responsible for checking the receipt and chain, recording and publishing the actual deployed address/transaction, matching deployed bytecode to this build, and telling players the contract address and rules. No deployment has been broadcast by this assignment. An independent agent reviews the logic, commitments, deadline boundaries, tests, and script; its findings and limitations are recorded in `REVIEW.md`. This review and passing tests are not a formal security audit.
