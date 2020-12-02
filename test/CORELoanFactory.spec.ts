import { expect } from 'chai'
import { Contract } from 'ethers'
import { ethers, upgrades } from 'hardhat'

const CORE = '0x62359Ed7505Efc61FF1D56fEF82158CcaffA23D7'
const FactoryContractName = 'CORELoanFactory'
const FactoryContractTestName = 'CORELoanFactoryUpgradeTest'

describe('CORE Loan Factory ', () => {
  let factory: Contract

  beforeEach(async () => {
    const CORELoanFactory = await ethers.getContractFactory(FactoryContractName)
    factory = await CORELoanFactory.deploy()
    await factory.deployed()
    await factory.initialize()
  })

  it('Should upgrade successfully', async () => {
    const Factory = await ethers.getContractFactory(FactoryContractName);
    const FactoryTest = await ethers.getContractFactory(FactoryContractTestName);

    const instance = await upgrades.deployProxy(Factory);
    const upgraded = await upgrades.upgradeProxy(instance.address, FactoryTest)

    expect(instance.address).to.equal(upgraded.address)

    const value = await upgraded.CORE();
    
    expect(value).to.equal(CORE);
  })

  it('Should create loan successfully', async () => {
    await expect(factory.createLoan(CORE, 10, 10, 12, 13)).to.emit(factory, 'LoanCreated')
  })
})
