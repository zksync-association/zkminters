import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

const MINTABLE_ADDRESS = ""; // TODO: Update this to the actual mintable address.
const ADMIN_ACCOUNT = ""; // TODO: Update this to the actual admin account.
const MINT_DELAY = 86400; // TODO: Update this to the actual mint delay. Currently set to 24 hours.
const SALT = ""; // TODO: Update this to the actual salt.

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkMinterDelayV1";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [MINTABLE_ADDRESS, ADMIN_ACCOUNT, MINT_DELAY];
  const customData = { salt: SALT };
  const delayMinter = await deployer.deploy(contract, constructorArgs, "create2", {
    customData,
  });

  console.log("constructor args:" + delayMinter.interface.encodeDeploy(constructorArgs));

  const contractAddress = await delayMinter.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const mintDelay = await delayMinter.mintDelay();
  console.log(`The mint delay is set to: ${mintDelay}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});