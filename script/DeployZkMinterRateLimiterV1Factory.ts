import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, utils } from "zksync-ethers";
import * as hre from "hardhat";
import * as fs from "fs";
import * as path from "path";

// Read the bytecode hash from ZkMinterRateLimiterV1.json
// Verify the zksolc version used to compile the contract, the hash changes with different versions
const zkMinterRateLimiterPath = path.join(
  __dirname,
  "../artifacts-zk/src/ZkMinterRateLimiterV1.sol/ZkMinterRateLimiterV1.json"
);
const zkMinterRateLimiterJson = JSON.parse(
  fs.readFileSync(zkMinterRateLimiterPath, "utf8")
);
const BYTECODE_HASH = utils.hashBytecode(zkMinterRateLimiterJson.bytecode);

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkMinterRateLimiterV1Factory";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [BYTECODE_HASH];
  const factory = await deployer.deploy(contract, constructorArgs, 'create2');

  console.log(
    "constructor args: " + factory.interface.encodeDeploy(constructorArgs)
  );

  const contractAddress = await factory.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const bytecodeHash = await factory.BYTECODE_HASH();
  console.log(`The BYTECODE_HASH is set to: ${bytecodeHash}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
