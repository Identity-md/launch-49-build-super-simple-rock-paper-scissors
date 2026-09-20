# Independent implementation review

A separate review agent (`independent_review`) inspected the final contract, deployment script, tests, Foundry configuration, and README independently of the implementing agent on 2026-09-19. This is an independent implementation review within this assignment, not external certification, a formal security audit, or live Sepolia verification.

**Result: no blocking correctness findings.**

## Findings and disposition

- **Low severity, resolved:** allowing the second player to copy the first player's commitment would let them copy the revealed preimage and force a draw. The contract now rejects equal commitments within a game with `CopiedCommitment`. Regression tests exercise both commit orders, verify rejection leaves the deadline unset, and recover with a fresh salt.
- **Accepted protocol limitation:** the requested hash covers move and salt, without player/game/chain/contract domain separation. Each player must use a fresh, unpredictable 32-byte salt for every game. A participant can front-run an opponent's pending commitment with the same hash, forcing the opponent to choose a fresh salt and retry. The final README documents this caveat. Cross-game salt/preimage reuse is unsafe.
- **Accepted liveness limitation:** there is no commitment timeout. An uncooperative opponent can leave a game pending indefinitely. This is documented; no funds become locked and players can create new games.

## Logic reviewed

The reviewer independently checked all nine move pairs and both reveal orders, player authorization, commitment immutability, invalid-preimage and invalid-move rejection, and immutable settlement. Rock beats scissors, paper beats rock, scissors beats paper, and equal moves draw.

The second commitment alone starts the fixed one-day window. Reveals require `block.timestamp < revealDeadline`; timeout settlement permits equality. A single valid revealer wins by forfeit; neither revealing produces a draw. Anyone may finalize a timeout. The contract performs no external calls and has no owner, administrative methods, upgrades, or payable methods.

The deployment script restricts execution to chain IDs 31337 and 11155111. Broadcast markers surround exactly one deployment with no constructor arguments. The script reads no private keys or environment variables. The documented operator command explicitly selects Sepolia, a keystore signer, sender, and broadcast. No transaction was broadcast during implementation or review.

## Independent checks

- `forge test --offline`: **23 passed**, including two fuzz tests with 256 runs each.
- `forge script script/Deploy.s.sol:Deploy --offline`: **passed without RPC**, local simulation only.

The implementing agent additionally ran `forge build`, `forge test`, `forge fmt --check`, and the local deployment script with `--offline --chain 31337`; all passed. The Foundry profile defaults to offline compiler operation. Expected timestamp lint warnings concern the intentional timeout comparisons.

## Scope limits

Review and local tests do not establish live deployment correctness or guarantee security. The deployment operator remains responsible for signer custody, RPC/network selection, transaction approval, deployment receipt and bytecode checks, and publishing the verified address. Players remain responsible for private salts and timely transaction inclusion.
