import { BigNumber } from 'ethers'

export const WAD = BigNumber.from(10).pow(18)
export const HALF_WAD = WAD.div(2)

export const RAY = BigNumber.from(10).pow(27)
export const HALF_RAY = RAY.div(2)

export const WAD_RAY_RATIO = BigNumber.from(10).pow(9)

export const YEAR_IN_SECONDS = BigNumber.from('365').mul(24).mul(60).mul(60)
