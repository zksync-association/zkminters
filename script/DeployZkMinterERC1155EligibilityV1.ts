import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

const MINTABLE_ADDRESS = ""; // TODO: Update this to the actual mintable address.
const ADMIN_ACCOUNT = ""; // TODO: Update this to the actual admin account.
const ERC1155_ADDRESS = ""; // TODO: Update this to the actual ERC1155 address.
const TOKEN_ID = 0; // TODO: Update this to the actual token ID.
const BALANCE_THRESHOLD = 0; // TODO: Update this to the actual balance threshold.
const SALT = ""; // TODO: Update this to the actual salt.

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkMinterERC1155EligibilityV1";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [MINTABLE_ADDRESS, ADMIN_ACCOUNT, ERC1155_ADDRESS, TOKEN_ID, BALANCE_THRESHOLD];
  const customData = { salt: SALT };
  const minterERC1155 = await deployer.deploy(contract, constructorArgs, "create2", {
    customData,
  });

  console.log("constructor args:" + minterERC1155.interface.encodeDeploy(constructorArgs));

  const contractAddress = await minterERC1155.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const balanceThreshold = await minterERC1155.balanceThreshold();
  console.log(`The balance threshold is set to: ${balanceThreshold}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}); 