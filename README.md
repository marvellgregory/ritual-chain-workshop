# CommitRevealBounty — README

Privacy-Preserving AI Bounty Judge built on top of the Ritual Chain Workshop.

---

## The Problem This Solves

In the original workshop contract, every participant's answer was visible on-chain the moment they submitted it. This allowed later participants to read earlier answers and submit improved versions — which is unfair when only one person wins.

**This contract fixes that** using a commit-reveal scheme.

---

## New Bounty Lifecycle

### Phase 1 — Submission (before `submissionDeadline`)

Participants do NOT submit their real answer yet. Instead, they submit a **commitment hash** — a cryptographic fingerprint of their answer that reveals nothing about its content.

Generate the hash off-chain (JavaScript/ethers.js):

```js
const salt = ethers.randomBytes(32); // random secret — save this!
const commitment = ethers.solidityPackedKeccak256(
  ["string", "bytes32", "address", "uint256"],
  [myAnswer, salt, myWalletAddress, bountyId]
);
await contract.submitCommitment(bountyId, commitment);
```

> Think of this like sealing your answer in an envelope and handing it to the judge. Nobody can read it until you open it.

---

### Phase 2 — Reveal (after `submissionDeadline`, before `revealDeadline`)

Now participants reveal their real answer and the salt they used. The contract re-hashes it and checks it matches their original commitment. If it doesn't match — the submission is rejected and not eligible for judging.

```js
await contract.revealAnswer(bountyId, myAnswer, salt);
```

> This is like opening your sealed envelope. Everyone can now see your answer, but only AFTER everyone has already committed.

---

### Phase 3 — Judging (after `revealDeadline`)

The bounty owner collects all revealed answers and sends them to Ritual AI in **one batch call** — not one LLM call per answer. Ritual AI scores them together and returns a ranking.

```js
const [addrs, answers] = await contract.getRevealedAnswers(bountyId);
// Build the LLM input (JSON) with all revealed answers
// Send to Ritual AI executor
// Store result on-chain
await contract.judgeAll(bountyId, llmInputBytes);
```

---

### Phase 4 — Finalization (human decision)

AI recommends a winner. The owner reviews and finalizes by passing the winner's index in the participants array. The contract pays the reward automatically.

```js
await contract.finalizeWinner(bountyId, winnerIndex);
```

> AI recommends — human decides. The owner always has final say.

---

## Key Contract Rules

| Rule | Why |
|---|---|
| One commitment per participant | Prevents spamming multiple bets |
| Commitment must match on reveal | Proves you didn't change your answer after seeing others |
| Unrevealed answers are excluded from judging | If you don't reveal, you forfeit eligibility |
| Owner can only judge after reveal deadline | Ensures all reveals are in before AI sees them |
| Owner can only finalize after judging | Ensures AI output is recorded before payout |
| Only one winner gets the reward | Clean payout, no partial splits |

---

## Architecture Note: Commit-Reveal vs Ritual-Native Encrypted Submissions

| Property | Commit-Reveal (Required Track) | Ritual-Native TEE (Advanced Track) |
|---|---|---|
| Are answers public before judging? | Yes — after the reveal phase | No — encrypted until judging is complete |
| What's stored on-chain? | Commitment hashes, then revealed answers | Encrypted ciphertexts only |
| How does AI see answers? | Plaintext batch after reveal | TEE decrypts privately, AI never exposes plaintext on-chain |
| Complexity | Moderate — works on any EVM chain | High — requires Ritual TEE infrastructure |
| Best for | Most bounty use cases | High-stakes competitions where even pre-judge visibility is unfair |

**Tradeoff:** Commit-reveal still makes answers public during the reveal phase (before AI judging). Ritual-native TEE keeps answers encrypted even from other participants right up until the AI judging completes and a winner is declared.

---

## Reflection: What Should Be Public, Hidden, or Decided by AI vs Human?

In a fair bounty system, the question and reward should always be public — participants need to know what they're competing for. During the submission phase, answers must stay hidden to prevent copying; the commit-reveal scheme achieves this on any EVM chain, while Ritual's TEE-backed execution can go further by keeping answers encrypted even during the reveal and judging phases.

The AI should handle objective scoring and ranking of submissions against the rubric, since it can evaluate all answers together without bias and at scale. However, the final payout decision should remain with the human bounty owner — they can catch edge cases, verify context, and override AI recommendations where needed. Automatic payouts from raw AI output carry risk because the result format must be parsed and validated carefully; a human checkpoint prevents errors from triggering irreversible on-chain transfers.

What should never be public: individual answers before judging, participant salts (which could allow commitment forgery if revealed early), and any private rubric criteria that could be gamed if known in advance.

---

## Folder Structure

```
ritual-bounty/
├── contracts/
│   └── CommitRevealBounty.sol   ← main contract
├── test/
│   └── CommitRevealBounty.test.js  ← test plan
└── README.md
```
