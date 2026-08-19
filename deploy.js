const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  // Configuration
  const REGISTRATION_FEE = hre.ethers.parseEther("0.1");    // 0.1 BOT to register
  const REWARD_PER_SUBMISSION = hre.ethers.parseEther("0.005"); // 0.005 BOT per data submission
  const HEARTBEAT_INTERVAL = 24 * 60 * 60;                   // 24 hours

  // Deploy
  const Registry = await hre.ethers.getContractFactory("DePINRegistry");
  const registry = await Registry.deploy(
    REGISTRATION_FEE,
    REWARD_PER_SUBMISSION,
    HEARTBEAT_INTERVAL
  );
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  console.log("DePINRegistry deployed to:", address);
  console.log("View on explorer: https://scan.botchain.ai/address/" + address);

  // Optionally fund the reward pool
  // const fundTx = await registry.fundRewards({ value: hre.ethers.parseEther("500") });
  // await fundTx.wait();
  // console.log("Funded reward pool with 500 BOT");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
