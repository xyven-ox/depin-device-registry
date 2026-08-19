const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("DePINRegistry", function () {
  let registry, owner, alice, bob;
  const REG_FEE = ethers.parseEther("0.1");
  const REWARD = ethers.parseEther("0.005");
  const HEARTBEAT = 24 * 60 * 60; // 24h

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    const Registry = await ethers.getContractFactory("DePINRegistry");
    registry = await Registry.deploy(REG_FEE, REWARD, HEARTBEAT);
    await registry.waitForDeployment();

    // Fund reward pool
    await registry.fundRewards({ value: ethers.parseEther("100") });
  });

  describe("Device Registration", function () {
    it("should register a device with correct fee", async function () {
      await registry.connect(alice).registerDevice("SENSOR-001", '{"model":"T100","location":"NYC"}', 0, { value: REG_FEE });
      const count = await registry.getDeviceCount();
      expect(count).to.equal(1);
    });

    it("should reject registration with insufficient fee", async function () {
      await expect(
        registry.connect(alice).registerDevice("SENSOR-002", "{}", 0, { value: ethers.parseEther("0.01") })
      ).to.be.revertedWith("Insufficient registration fee");
    });

    it("should reject duplicate device IDs", async function () {
      await registry.connect(alice).registerDevice("SENSOR-001", "{}", 0, { value: REG_FEE });
      await expect(
        registry.connect(bob).registerDevice("SENSOR-001", "{}", 0, { value: REG_FEE })
      ).to.be.revertedWith("Device ID already registered");
    });

    it("should track owner devices", async function () {
      await registry.connect(alice).registerDevice("DEV-A", "{}", 0, { value: REG_FEE });
      await registry.connect(alice).registerDevice("DEV-B", "{}", 1, { value: REG_FEE });
      const devices = await registry.getOwnerDevices(alice.address);
      expect(devices.length).to.equal(2);
    });

    it("should emit DeviceRegistered event", async function () {
      await expect(
        registry.connect(alice).registerDevice("DEV-X", '{"type":"gpu"}', 1, { value: REG_FEE })
      ).to.emit(registry, "DeviceRegistered");
    });
  });

  describe("Data Submission", function () {
    beforeEach(async function () {
      await registry.connect(alice).registerDevice("SENSOR-001", "{}", 0, { value: REG_FEE });
    });

    it("should accept data submission and pay reward", async function () {
      const dataHash = ethers.keccak256(ethers.toUtf8Bytes("temperature:22.5,humidity:60"));
      const balBefore = await ethers.provider.getBalance(alice.address);

      const tx = await registry.connect(alice).submitData(0, dataHash);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;

      const balAfter = await ethers.provider.getBalance(alice.address);
      // Balance should increase by reward minus gas
      expect(balAfter + gasUsed - balBefore).to.be.closeTo(REWARD, ethers.parseEther("0.0001"));
    });

    it("should reject submission from non-owner", async function () {
      const dataHash = ethers.keccak256(ethers.toUtf8Bytes("test"));
      await expect(registry.connect(bob).submitData(0, dataHash)).to.be.revertedWith("Not device owner");
    });

    it("should increment submission count", async function () {
      const hash1 = ethers.keccak256(ethers.toUtf8Bytes("data1"));
      const hash2 = ethers.keccak256(ethers.toUtf8Bytes("data2"));
      await registry.connect(alice).submitData(0, hash1);
      await registry.connect(alice).submitData(0, hash2);

      const device = await registry.getDevice(0);
      expect(device.totalSubmissionsCount).to.equal(2);
    });
  });

  describe("Device Management", function () {
    beforeEach(async function () {
      await registry.connect(alice).registerDevice("SENSOR-001", "{}", 0, { value: REG_FEE });
    });

    it("should allow owner to deactivate", async function () {
      await registry.connect(alice).deactivateDevice(0);
      const device = await registry.getDevice(0);
      expect(device.status).to.equal(1); // Inactive = 1 (actually 0=Inactive)
    });

    it("should allow owner to update metadata", async function () {
      await registry.connect(alice).updateDevice(0, '{"location":"London"}');
      const device = await registry.getDevice(0);
      expect(device.metadata).to.equal('{"location":"London"}');
    });

    it("should allow admin to suspend device", async function () {
      await registry.suspendDevice(0);
      const device = await registry.getDevice(0);
      expect(device.status).to.equal(2); // Suspended
    });

    it("should detect stale devices", async function () {
      await time.increase(HEARTBEAT + 1);
      expect(await registry.isDeviceStale(0)).to.be.true;
    });
  });

  describe("Admin", function () {
    it("should allow owner to change registration fee", async function () {
      const newFee = ethers.parseEther("0.5");
      await registry.setRegistrationFee(newFee);
      expect(await registry.registrationFee()).to.equal(newFee);
    });

    it("should allow owner to change reward rate", async function () {
      const newReward = ethers.parseEther("0.01");
      await registry.setRewardPerSubmission(newReward);
      expect(await registry.rewardPerSubmission()).to.equal(newReward);
    });

    it("should allow pause/unpause", async function () {
      await registry.pause();
      await expect(
        registry.connect(alice).registerDevice("NEW", "{}", 0, { value: REG_FEE })
      ).to.be.reverted;
      await registry.unpause();
      await registry.connect(alice).registerDevice("NEW", "{}", 0, { value: REG_FEE });
    });
  });
});
