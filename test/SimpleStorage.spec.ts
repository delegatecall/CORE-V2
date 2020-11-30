import { expect, use } from 'chai'
import { Contract } from 'ethers'
import { deployContract, MockProvider, solidity } from 'ethereum-waffle'
import SimpleStorage from '../build/SimpleStorage.json'

use(solidity)

describe('Simple Storage', () => {
  const [wallet, walletTo] = new MockProvider().getWallets()
  let storage: Contract

  beforeEach(async () => {
    storage = await deployContract(wallet, SimpleStorage)
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
