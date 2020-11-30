import { expect, use } from 'chai'
import { Contract } from 'ethers'
import { deployContract, MockProvider, solidity } from 'ethereum-waffle'
import Factory from '../build/CORELoanFactory.json'

const CORE = '0x62359Ed7505Efc61FF1D56fEF82158CcaffA23D7'
use(solidity)

describe('CORE Loan Factory ', () => {
  const [wallet, walletTo] = new MockProvider().getWallets()
  let factory: Contract

  beforeEach(async () => {
    factory = await deployContract(wallet, Factory)
  })

  it('Should Create Loan Successfully ', async () => {
    await expect(factory.createLoan(CORE, 10, 11, 12, 13)).to.emit(factory, 'LoanCreated')
  })
})
