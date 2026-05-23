import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  // 1. Deploy PayoraVerifier
  console.log("\n1. Deploying PayoraVerifier...");
  const VerifierFactory = await ethers.getContractFactory("PayoraVerifier");
  const verifier = await VerifierFactory.deploy(ethers.ZeroAddress, 0); // zero attestation, TEE type
  await verifier.waitForDeployment();
  const verifierAddr = await verifier.getAddress();
  console.log("PayoraVerifier deployed to:", verifierAddr);

  // 2. Deploy PayoraNFT implementation
  console.log("\n2. Deploying PayoraNFT implementation...");
  const NFTFactory = await ethers.getContractFactory("PayoraNFT");
  const nftImpl = await NFTFactory.deploy();
  await nftImpl.waitForDeployment();
  const nftImplAddr = await nftImpl.getAddress();
  console.log("PayoraNFT implementation:", nftImplAddr);

  // 3. Deploy UpgradeableBeacon
  console.log("\n3. Deploying UpgradeableBeacon...");
  const BeaconFactory = await ethers.getContractFactory("UpgradeableBeacon");
  const beacon = await BeaconFactory.deploy(nftImplAddr, deployer.address);
  await beacon.waitForDeployment();
  const beaconAddr = await beacon.getAddress();
  console.log("UpgradeableBeacon deployed to:", beaconAddr);

  // 4. Prepare initialization data
  const nftName = process.env.ZG_NFT_NAME || "Payora iNFT";
  const nftSymbol = process.env.ZG_NFT_SYMBOL || "Payora";
  const chainURL = process.env.ZG_RPC_URL || "https://evmrpc-testnet.0g.ai";
  const indexerURL =
    process.env.ZG_INDEXER_URL || "https://indexer-storage-testnet-turbo.0g.ai";

  const initData = NFTFactory.interface.encodeFunctionData("initialize", [
    nftName,
    nftSymbol,
    verifierAddr,
    chainURL,
    indexerURL,
  ]);

  // 5. Deploy BeaconProxy
  console.log("\n4. Deploying BeaconProxy...");
  const ProxyFactory = await ethers.getContractFactory("BeaconProxy");
  const proxy = await ProxyFactory.deploy(beaconAddr, initData);
  await proxy.waitForDeployment();
  const proxyAddr = await proxy.getAddress();
  console.log("PayoraNFT proxy deployed to:", proxyAddr);

  // 6. Verify initialization
  const PayoraNFT = NFTFactory.attach(proxyAddr);
  const name = await PayoraNFT.name();
  const symbol = await PayoraNFT.symbol();
  console.log(`\nVerification: name="${name}", symbol="${symbol}"`);

  console.log("\n=== Deployment Complete ===");
  console.log("PayoraVerifier:", verifierAddr);
  console.log("PayoraNFT (proxy):", proxyAddr);
  console.log("PayoraNFT (impl):", nftImplAddr);
  console.log("Beacon:", beaconAddr);
  console.log("\nAdd to your .env:");
  console.log(`Payora_NFT_ADDRESS=${proxyAddr}`);
  console.log(`Payora_VERIFIER_ADDRESS=${verifierAddr}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });