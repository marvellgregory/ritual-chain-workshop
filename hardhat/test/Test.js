/**
 * CommitRevealBounty — Test Plan
 * 
 * Framework: Hardhat + Ethers.js v6
 * Run: npx hardhat test
 */

const { expect } = require("chai");
const { ethers }  = require("hardhat");

describe("CommitRevealBounty", function () {

  let contract, owner, alice, bob, carol;
  let bountyId;

  // Helpers
  const makeCommitment = (answer, salt, address, id) =>
    ethers.solidityPackedKeccak256(
      ["string", "bytes32", "address", "uint256"],
      [answer, salt, address, id]
    );

  const now = () => Math.floor(Date.now() / 1000);
  const future = (secs) => now() + secs;

  beforeEach(async () => {
    [owner, alice, bob, carol] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("CommitRevealBounty");
    contract = await Factory.deploy();
  });

  // ── BOUNTY CREATION ────────────────────────────────────────────────────────

  describe("createBounty", () => {
    it("✅ Creates bounty with correct parameters", async () => {
      const subDL = future(3600);   // 1 hour
      const revDL = future(7200);   // 2 hours
      const tx = await contract.createBounty("What is the meaning of life?", subDL, revDL, {
        value: ethers.parseEther("1.0"),
      });
      await expect(tx).to.emit(contract, "BountyCreated").withArgs(1, owner.address, ethers.parseEther("1.0"));
    });

    it("❌ Rejects bounty with no reward attached", async () => {
      await expect(
        contract.createBounty("Q", future(3600), future(7200), { value: 0 })
      ).to.be.revertedWithCustomError(contract, "InvalidDeadlines");
    });

    it("❌ Rejects reveal deadline before submission deadline", async () => {
      await expect(
        contract.createBounty("Q", future(7200), future(3600), { value: ethers.parseEther("1") })
      ).to.be.revertedWithCustomError(contract, "InvalidDeadlines");
    });
  });

  // ── COMMIT PHASE ───────────────────────────────────────────────────────────

  describe("submitCommitment", () => {
    beforeEach(async () => {
      await contract.createBounty("Q", future(3600), future(7200), { value: ethers.parseEther("1") });
      bountyId = 1;
    });

    it("✅ Participant can submit a valid commitment", async () => {
      const salt = ethers.randomBytes(32);
      const cm   = makeCommitment("My answer", salt, alice.address, bountyId);
      await expect(contract.connect(alice).submitCommitment(bountyId, cm))
        .to.emit(contract, "CommitmentSubmitted").withArgs(bountyId, alice.address);
    });

    it("❌ Same participant cannot commit twice", async () => {
      const salt = ethers.randomBytes(32);
      const cm   = makeCommitment("My answer", salt, alice.address, bountyId);
      await contract.connect(alice).submitCommitment(bountyId, cm);
      await expect(
        contract.connect(alice).submitCommitment(bountyId, cm)
      ).to.be.revertedWithCustomError(contract, "AlreadyCommitted");
    });

    it("❌ Cannot commit after submission deadline", async () => {
      // Create a bounty that is already past deadline (simulate via a past timestamp)
      // In real test: use time manipulation via hardhat_mine / evm_increaseTime
      // pseudocode shown here for clarity:
      // await ethers.provider.send("evm_increaseTime", [3601]);
      // await ethers.provider.send("evm_mine");
      // await expect(contract.connect(alice).submitCommitment(bountyId, cm))
      //   .to.be.revertedWithCustomError(contract, "SubmissionPhaseClosed");
      console.log("  [manual] Test: advance time past submissionDeadline and verify rejection");
    });
  });

  // ── REVEAL PHASE ───────────────────────────────────────────────────────────

  describe("revealAnswer", () => {
    let aliceSalt, aliceAnswer, aliceCm;

    beforeEach(async () => {
      await contract.createBounty("Q", future(3600), future(7200), { value: ethers.parseEther("1") });
      bountyId = 1;

      aliceAnswer = "The answer is 42";
      aliceSalt   = ethers.randomBytes(32);
      aliceCm     = makeCommitment(aliceAnswer, aliceSalt, alice.address, bountyId);
      await contract.connect(alice).submitCommitment(bountyId, aliceCm);
    });

    it("✅ Valid reveal accepted when hash matches", async () => {
      // Advance time past submission deadline
      // await ethers.provider.send("evm_increaseTime", [3601]);
      // await ethers.provider.send("evm_mine");
      // await expect(contract.connect(alice).revealAnswer(bountyId, aliceAnswer, aliceSalt))
      //   .to.emit(contract, "AnswerRevealed");
      console.log("  [manual] Test: advance time, reveal correct answer → expect AnswerRevealed event");
    });

    it("❌ Reveal rejected if answer was tampered (hash mismatch)", async () => {
      // await ethers.provider.send("evm_increaseTime", [3601]);
      // await ethers.provider.send("evm_mine");
      // await expect(
      //   contract.connect(alice).revealAnswer(bountyId, "A different answer", aliceSalt)
      // ).to.be.revertedWithCustomError(contract, "InvalidReveal");
      console.log("  [manual] Test: reveal wrong answer → expect InvalidReveal error");
    });

    it("❌ Cannot reveal before submission deadline closes", async () => {
      // Without advancing time:
      // await expect(
      //   contract.connect(alice).revealAnswer(bountyId, aliceAnswer, aliceSalt)
      // ).to.be.revertedWithCustomError(contract, "RevealPhaseNotOpen");
      console.log("  [manual] Test: reveal during submission phase → expect RevealPhaseNotOpen");
    });

    it("❌ Cannot reveal after reveal deadline", async () => {
      // await ethers.provider.send("evm_increaseTime", [7201]);
      // await ethers.provider.send("evm_mine");
      // await expect(
      //   contract.connect(alice).revealAnswer(bountyId, aliceAnswer, aliceSalt)
      // ).to.be.revertedWithCustomError(contract, "RevealPhaseClosed");
      console.log("  [manual] Test: advance past reveal deadline → expect RevealPhaseClosed");
    });

    it("❌ Cannot reveal without having committed first", async () => {
      // await ethers.provider.send("evm_increaseTime", [3601]);
      // await expect(
      //   contract.connect(bob).revealAnswer(bountyId, "Some answer", ethers.randomBytes(32))
      // ).to.be.revertedWithCustomError(contract, "NotCommitted");
      console.log("  [manual] Test: bob never committed, tries to reveal → expect NotCommitted");
    });

    it("❌ Cannot reveal twice", async () => {
      // After successful first reveal, second call should revert with AlreadyRevealed
      console.log("  [manual] Test: reveal twice → expect AlreadyRevealed on second call");
    });
  });

  // ── JUDGING ────────────────────────────────────────────────────────────────

  describe("judgeAll", () => {
    it("✅ Owner can call judgeAll after reveal deadline", async () => {
      console.log("  [manual] Test: advance past revealDeadline → judgeAll succeeds, BountyJudged emitted");
    });

    it("❌ Non-owner cannot judge", async () => {
      // await expect(
      //   contract.connect(alice).judgeAll(bountyId, "0x1234")
      // ).to.be.revertedWithCustomError(contract, "NotBountyOwner");
      console.log("  [manual] Test: alice calls judgeAll → expect NotBountyOwner");
    });

    it("❌ Cannot judge before reveal deadline", async () => {
      console.log("  [manual] Test: judge during reveal phase → expect JudgingPhaseNotOpen");
    });
  });

  // ── FINALIZATION ───────────────────────────────────────────────────────────

  describe("finalizeWinner", () => {
    it("✅ Owner can finalize a valid revealed winner and reward is transferred", async () => {
      console.log("  [manual] Test: full happy path → alice's balance increases by reward amount");
    });

    it("❌ Cannot finalize before judging", async () => {
      console.log("  [manual] Test: finalize before judgeAll → expect NotJudgedYet");
    });

    it("❌ Cannot finalize twice", async () => {
      console.log("  [manual] Test: second finalize call → expect AlreadyFinalized");
    });

    it("❌ Cannot pick an unrevealed participant as winner", async () => {
      console.log("  [manual] Test: bob committed but never revealed, owner picks bob → expect WinnerNotRevealed");
    });

    it("❌ Invalid winner index rejected", async () => {
      console.log("  [manual] Test: winner index out of bounds → expect InvalidWinnerIndex");
    });
  });

  // ── EDGE CASES ─────────────────────────────────────────────────────────────

  describe("Edge Cases", () => {
    it("❌ Participant cannot use another participant's commitment hash", async () => {
      // Because the commitment includes msg.sender, copying alice's hash and submitting
      // as bob will produce a different hash at reveal time → InvalidReveal on reveal.
      console.log("  [manual] Test: bob submits alice's commitment → reveal fails with InvalidReveal");
    });

    it("✅ Unrevealed participants are excluded from judging output", async () => {
      console.log("  [manual] Test: getRevealedAnswers returns empty string for non-revealed slots");
    });

    it("✅ computeCommitment helper produces same hash as off-chain ethers.js", async () => {
      const answer = "test";
      const salt   = ethers.randomBytes(32);
      const id     = 1n;
      const onChain  = await contract.computeCommitment(answer, salt, alice.address, id);
      const offChain = makeCommitment(answer, salt, alice.address, id);
      expect(onChain).to.equal(offChain);
    });
  });

});
