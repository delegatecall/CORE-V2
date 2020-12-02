import { expect } from 'chai'
import { Contract } from 'ethers'
import { ethers } from 'hardhat'

describe('Simple Storage', () => {
  let storage: Contract
  beforeEach(async () => {
    const SimpleStorage = await ethers.getContractFactory('SimpleStorage')
    storage = await SimpleStorage.deploy()
    await storage.deployed()
  })

  it('Should get the initial storage value successfully', async () => {
    expect(await storage.get()).to.equal(0)
  })

  it('Should write the storage value successfully', async () => {
    const newValue = 10
    await storage.set(newValue)
    expect(await storage.get()).to.equal(newValue)
  })
})
