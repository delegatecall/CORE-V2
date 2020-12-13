import { BigNumber } from 'ethers'
import { ethers } from 'hardhat'
import { RAY, YEAR_IN_SECONDS } from './constants'
const { provider } = ethers
export async function getTransactionTimeStamp(txHash: string) {
  const block = await provider.getBlock(txHash)
  return block.timestamp
}

export function calculateCompoundedInterest(rate: BigNumber, timeInSec: number): BigNumber {
  return rate.div(YEAR_IN_SECONDS).add(RAY).rayPow(BigNumber.from(timeInSec))
}

export async function advanceByHours(hours: number) {
  //   await advanceTimeAndBlock(60 * 60 * hours)
  console.log('advance time', hours)
}

export async function impersonate(address: string) {
  console.log(`Impersonating ${address}`)
  await ethers.provider.send('hardhat_impersonateAccount', [address])
}

export async function stopImpersonate(address: string) {
  await provider.send('hardhat_stopImpersonatingAccount', [address])
}

export async function resetNetwork() {
  await provider.send('hardhat_reset', [
    {
      forking: {
        url: 'https://eth-mainnet.alchemyapi.io/v2/TsLEJAhX87icgMO7ZVyPcpeEgpFEo96O',
        blockNumber: 11123663,
      },
    },
  ])
}

export async function advanceTimeAndBlock(time: number) {
  await advanceTime(time)
  await advanceBlock()

  return await provider.getBlock('latest')
}

export async function advanceTime(time: number) {
  await provider.send('evm_increaseTime', [time])
}

export async function advanceBlock() {
  await provider.send('evm_mine', [])
}
