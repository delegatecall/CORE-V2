import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { create } from 'domain'
import { Contract } from 'ethers'
import { ethers, upgrades } from 'hardhat'
import { calculateCompoundedInterest, getTransactionTimeStamp, mulByRay, resetNetwork } from './utils'
const {
  utils: { parseEther },
  BigNumber,
} = ethers

describe('CORELoan Integration test', () => {
  let loan: Contract
  let treasury: Contract
  let priceOracle: Contract
  let users: SignerWithAddress[]

  beforeEach(async () => {
    // await resetNetwork()
    const CORELoan = await ethers.getContractFactory('CORELoan')
    loan = await upgrades.deployProxy(CORELoan, { unsafeAllowCustomTypes: true })
    await loan.deployed()

    const Treasury = await ethers.getContractFactory('Treasury')
    treasury = await upgrades.deployProxy(Treasury)
    await treasury.deployed()

    const PriceOracle = await ethers.getContractFactory('PriceOracle')
    priceOracle = await upgrades.deployProxy(PriceOracle)
    await priceOracle.deployed()
    await loan.setAddresses(priceOracle.address, treasury.address)
    users = await ethers.getSigners()
    console.log('Loan Address:', loan.address)
    console.log('Oracle Address:', priceOracle.address)
    console.log('Treasury Address:', treasury.address)
  })

  it('Should initialze eth reserve data correctly', async () => {
    const reserveData = await loan.getEthReserveData()
    const createdAt = await getTransactionTimeStamp(loan.deployTransaction.blockHash!)
    const [balance, rate, index, threshold, timestamp] = await loan.getEthReserveData()
    expect(balance).to.equal(0)
    expect(rate).to.equal(mulByRay(5))
    expect(index, 'match cumulativeindex').to.equal(mulByRay(1))
    expect(threshold).to.equal(75)
    expect(timestamp).to.equal(createdAt)
  })

  it('Should Set PriceOracle and Treasury successfully', async () => {
    expect(await loan.priceOracle()).equal(priceOracle.address)
    expect(await loan.treasury()).equal(treasury.address)
  })

  it('Should borrow successfully with right input', async () => {
    const coreAmount = parseEther('1.5')
    const coreBottomPrice = await priceOracle.getCOREBottomPrice()
    const [, previousInterestRate, previousIndex, , previousTimestamp] = await loan.getEthReserveData()

    const borrowInEth = coreAmount.mul(coreBottomPrice).div(parseEther('1'))
    const borrowTransaction = await loan.borrow(coreAmount)
    const loanCreatedAt = await getTransactionTimeStamp(borrowTransaction.blockHash)

    const [balance, rate, index, threshold, timestamp] = await loan.getEthReserveData()

    const compoundedInterest = calculateCompoundedInterest(previousInterestRate, timestamp.sub(previousTimestamp))
    const cumulativeindex = compoundedInterest.rayMul(previousIndex)
    expect(balance).to.equal(borrowInEth)
    expect(rate).to.equal(mulByRay(5))
    expect(index, 'match cumulativeindex').to.equal(cumulativeindex)
    expect(threshold).to.equal(75)
    expect(timestamp).to.equal(loanCreatedAt)

    const [principal, interest, coreAsCollateral, corePrice] = await loan.getUserLoanInfo(users[0].address)
    expect(principal, 'principal').to.equal(borrowInEth)
    expect(interest).to.equal(0)
    expect(coreAsCollateral).to.equal(coreAmount)

    // TODO fix the timestamp later
    // .withArgs(users[0].address, expectedBorrow, mulByRay(5), getCreatedAt())
  })
})
