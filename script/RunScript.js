// script/RunScript.js
const { execSync } = require('child_process');

const scriptName = process.argv[2];
if (!scriptName) {
  console.error('Please provide a script name');
  process.exit(1);
}

// Get additional arguments (like --network)
const additionalArgs = process.argv.slice(3).join(' ');
execSync(`npx hardhat clean && npx hardhat compile && npx hardhat run script/${scriptName} ${additionalArgs}`, { stdio: 'inherit' });
