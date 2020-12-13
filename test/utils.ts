import { BigNumber } from 'ethers'
import { network, ethers } from 'hardhat'
import { RAY, YEAR_IN_SECONDS } from './constants'

export async function getTransactionTimeStamp(txHash: string) {
  const block = await ethers.provider.getBlock(txHash)
  return block.timestamp
}

//RAY is 1e27 for high accurate decimal calulation
export function mulByRay(num: number): BigNumber {
  return RAY.mul(num)
}

export function calculateCompoundedInterest(rate: BigNumber, timeInSec: number): BigNumber {
  return rate.div(YEAR_IN_SECONDS).add(mulByRay(1)).rayPow(BigNumber.from(timeInSec))
}

export async function advanceByHours(hours: number) {
  //   await advanceTimeAndBlock(60 * 60 * hours)
  console.log('advance time', hours)
}

export async function impersonate(address: string) {
  console.log(`Impersonating ${address}`)
  await network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [address],
  })
}

export async function resetNetwork() {
  console.log(network.provider.request)
  await network.provider.request({
    method: 'hardhat_reset',
    params: [
      {
        forking: {
          url: 'https://eth-mainnet.alchemyapi.io/v2/TsLEJAhX87icgMO7ZVyPcpeEgpFEo96O',
          blockNumber: 11123663,
        },
      },
    ],
  })
}
