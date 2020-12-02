// scripts/create-box.js
import { ethers, upgrades } from 'hardhat'

async function main() {
  const Factory = await ethers.getContractFactory("CORELoanFactory")
  const factory = await upgrades.deployProxy(Factory)
  await factory.deployed();
  console.log("Box deployed to:", factory.address);
}

main();