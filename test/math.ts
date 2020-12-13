import { BigNumber } from 'ethers'
import { HALF_RAY, RAY } from './constants'

declare module 'ethers' {
  interface BigNumber {
    // ray: () => BigNumber
    // wad: () => BigNumber
    // halfRay: () => BigNumber
    // halfWad: () => BigNumber
    // wadMul: (a: BigNumber) => BigNumber
    // wadDiv: (a: BigNumber) => BigNumber
    rayMul: (a: BigNumber) => BigNumber
    // rayDiv: (a: BigNumber) => BigNumber
    // rayToWad: () => BigNumber
    // wadToRay: () => BigNumber
    rayPow: (n: BigNumber) => BigNumber
  }
}

BigNumber.prototype.rayMul = function (a: BigNumber): BigNumber {
  return HALF_RAY.add(this.mul(a)).div(RAY)
}
BigNumber.prototype.rayPow = function (n: BigNumber): BigNumber {
  let z = !n.mod(2).eq(0) ? this : RAY
  let x = BigNumber.from(this)

  for (n = n.div(2); !n.eq(0); n = n.div(2)) {
    x = x.rayMul(x)

    if (!n.mod(2).eq(0)) {
      z = z.rayMul(x)
    }
  }
  return z
}
