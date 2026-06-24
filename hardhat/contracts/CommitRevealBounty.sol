// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CommitRevealBounty
 * @notice Privacy-preserving AI Bounty Judge using commit-reveal scheme.
 *
 * HOW IT WORKS (simple version):
 * 1. Owner creates a bounty with a reward and two deadlines.
 * 2. Participants submit a "locked box" (commitment hash) — not the real answer yet.
 * 3. After submission deadline, participants "open the box" (reveal answer + salt).
 * 4. Contract checks the box matches. If yes, answer is eligible for judging.
 * 5. After reveal deadline, owner calls Ritual AI to judge all revealed answers.
 * 6. Owner picks the winner and pays out the reward.
 */
contract CommitRevealBounty {

    // ─────────────────────────────────────────
    //  DATA STRUCTURES
    // ─────────────────────────────────────────

    struct Submission {
        bytes32 commitment;       // The "locked box" hash submitted before deadline
        string  answer;           // The revealed answer (empty until reveal phase)
        bytes32 salt;             // Random secret used to lock the box
        bool    committed;        // Has this participant submitted a commitment?
        bool    revealed;         // Has this participant revealed their answer?
    }

    struct Bounty {
        address owner;            // Who created this bounty
        string  question;         // The bounty question / task
        uint256 reward;           // Prize in wei (ETH)
        uint256 submissionDeadline; // Participants must commit before this timestamp
        uint256 revealDeadline;     // Participants must reveal before this timestamp
        bool    judged;           // Has Ritual AI judged the submissions?
        bool    finalized;        // Has a winner been paid?
        address winner;           // Winner's address (set after finalization)
        address[] participants;   // All addresses that submitted a commitment
        bytes   judgingResult;    // Raw output from Ritual AI judge
    }

    // ─────────────────────────────────────────
    //  STATE
    // ─────────────────────────────────────────

    uint256 public bountyCount;

    // bountyId => Bounty
    mapping(uint256 => Bounty) public bounties;

    // bountyId => participant address => their submission
    mapping(uint256 => mapping(address => Submission)) public submissions;

    // ─────────────────────────────────────────
    //  EVENTS
    // ─────────────────────────────────────────

    event BountyCreated(uint256 indexed bountyId, address indexed owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed bountyId, address indexed participant);
    event AnswerRevealed(uint256 indexed bountyId, address indexed participant);
    event BountyJudged(uint256 indexed bountyId);
    event WinnerFinalized(uint256 indexed bountyId, address indexed winner, uint256 reward);

    // ─────────────────────────────────────────
    //  ERRORS
    // ─────────────────────────────────────────

    error NotBountyOwner();
    error SubmissionPhaseClosed();
    error RevealPhaseNotOpen();
    error RevealPhaseClosed();
    error JudgingPhaseNotOpen();
    error AlreadyCommitted();
    error NotCommitted();
    error AlreadyRevealed();
    error InvalidReveal();
    error NotJudgedYet();
    error AlreadyFinalized();
    error InvalidWinnerIndex();
    error WinnerNotRevealed();
    error TransferFailed();
    error InvalidDeadlines();

    // ─────────────────────────────────────────
    //  MODIFIERS
    // ─────────────────────────────────────────

    modifier onlyOwner(uint256 bountyId) {
        if (msg.sender != bounties[bountyId].owner) revert NotBountyOwner();
        _;
    }

    // ─────────────────────────────────────────
    //  CORE FUNCTIONS
    // ─────────────────────────────────────────

    /**
     * @notice Create a new bounty. Send ETH as the reward.
     * @param question   The task / question participants will answer.
     * @param subDeadline  Unix timestamp — submissions close at this time.
     * @param revDeadline  Unix timestamp — reveals close at this time (must be after subDeadline).
     */
    function createBounty(
        string calldata question,
        uint256 subDeadline,
        uint256 revDeadline
    ) external payable returns (uint256 bountyId) {
        if (subDeadline <= block.timestamp) revert InvalidDeadlines();
        if (revDeadline <= subDeadline)     revert InvalidDeadlines();
        if (msg.value == 0)                 revert InvalidDeadlines(); // must attach a reward

        bountyId = ++bountyCount;
        Bounty storage b = bounties[bountyId];
        b.owner              = msg.sender;
        b.question           = question;
        b.reward             = msg.value;
        b.submissionDeadline = subDeadline;
        b.revealDeadline     = revDeadline;

        emit BountyCreated(bountyId, msg.sender, msg.value);
    }

    /**
     * @notice Step 1 — Submit your "locked box" commitment hash.
     *
     * HOW TO MAKE THE HASH (off-chain, in JavaScript):
     *   const commitment = ethers.solidityPackedKeccak256(
     *     ["string", "bytes32", "address", "uint256"],
     *     [answer, salt, yourAddress, bountyId]
     *   );
     *
     * The salt is a random secret only YOU know.
     * The hash reveals nothing about your answer — only you can open it later.
     */
    function submitCommitment(uint256 bountyId, bytes32 commitment) external {
        Bounty storage b = bounties[bountyId];

        // Must be before submission deadline
        if (block.timestamp > b.submissionDeadline) revert SubmissionPhaseClosed();

        Submission storage s = submissions[bountyId][msg.sender];

        // One commitment per participant
        if (s.committed) revert AlreadyCommitted();

        s.commitment = commitment;
        s.committed  = true;
        b.participants.push(msg.sender);

        emit CommitmentSubmitted(bountyId, msg.sender);
    }

    /**
     * @notice Step 2 — Reveal your real answer after submission deadline.
     *
     * The contract will re-hash your answer+salt+address+bountyId
     * and verify it matches what you submitted. No match = rejected.
     */
    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external {
        Bounty storage b = bounties[bountyId];

        // Can only reveal AFTER submission deadline
        if (block.timestamp <= b.submissionDeadline) revert RevealPhaseNotOpen();

        // Can only reveal BEFORE reveal deadline
        if (block.timestamp > b.revealDeadline) revert RevealPhaseClosed();

        Submission storage s = submissions[bountyId][msg.sender];

        // Must have committed first
        if (!s.committed) revert NotCommitted();

        // Can only reveal once
        if (s.revealed) revert AlreadyRevealed();

        // Verify the revealed answer matches the original commitment
        bytes32 expectedHash = keccak256(
            abi.encodePacked(answer, salt, msg.sender, bountyId)
        );
        if (expectedHash != s.commitment) revert InvalidReveal();

        s.answer   = answer;
        s.salt     = salt;
        s.revealed = true;

        emit AnswerRevealed(bountyId, msg.sender);
    }

    /**
     * @notice Step 3 — Owner sends all revealed answers to Ritual AI for judging.
     *
     * llmInput is built off-chain: a JSON blob containing all revealed answers.
     * Ritual AI processes it in one batch and returns a result.
     * The result is stored on-chain for the owner to use when finalizing.
     *
     * NOTE: In a full Ritual integration, this would call an on-chain Ritual
     * executor. Here we store the llmInput result directly for the required track.
     */
    function judgeAll(uint256 bountyId, bytes calldata llmInput) external onlyOwner(bountyId) {
        Bounty storage b = bounties[bountyId];

        // Can only judge after the reveal deadline
        if (block.timestamp <= b.revealDeadline) revert JudgingPhaseNotOpen();

        // Can't judge twice
        if (b.judged) revert AlreadyFinalized();

        b.judgingResult = llmInput;
        b.judged = true;

        emit BountyJudged(bountyId);
    }

    /**
     * @notice Step 4 — Owner picks the winner by index in the participants array.
     *
     * AI recommends a winner, but the human owner makes the final call.
     * The winner must have a valid revealed answer.
     */
    function finalizeWinner(uint256 bountyId, uint256 winnerIndex) external onlyOwner(bountyId) {
        Bounty storage b = bounties[bountyId];

        // Must be judged first
        if (!b.judged) revert NotJudgedYet();

        // Can only finalize once
        if (b.finalized) revert AlreadyFinalized();

        // Index must be valid
        if (winnerIndex >= b.participants.length) revert InvalidWinnerIndex();

        address winnerAddr = b.participants[winnerIndex];

        // Winner must have revealed their answer
        if (!submissions[bountyId][winnerAddr].revealed) revert WinnerNotRevealed();

        b.winner    = winnerAddr;
        b.finalized = true;

        // Pay the winner
        (bool ok,) = winnerAddr.call{value: b.reward}("");
        if (!ok) revert TransferFailed();

        emit WinnerFinalized(bountyId, winnerAddr, b.reward);
    }

    // ─────────────────────────────────────────
    //  VIEW HELPERS
    // ─────────────────────────────────────────

    /// @notice Returns all revealed answers for a bounty (for Ritual AI input builder)
    function getRevealedAnswers(uint256 bountyId)
        external
        view
        returns (address[] memory addrs, string[] memory answers)
    {
        Bounty storage b = bounties[bountyId];
        uint256 count = b.participants.length;
        addrs   = new address[](count);
        answers = new string[](count);

        for (uint256 i = 0; i < count; i++) {
            address p = b.participants[i];
            addrs[i]   = p;
            // Only include revealed answers; unrevealed stay empty
            if (submissions[bountyId][p].revealed) {
                answers[i] = submissions[bountyId][p].answer;
            }
        }
    }

    /// @notice Returns participants list for a bounty
    function getParticipants(uint256 bountyId) external view returns (address[] memory) {
        return bounties[bountyId].participants;
    }

    /// @notice Helper to compute commitment hash off-chain (call this as a view)
    function computeCommitment(
        string calldata answer,
        bytes32 salt,
        address participant,
        uint256 bountyId
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(answer, salt, participant, bountyId));
    }
}
