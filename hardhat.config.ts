import { task, HardhatUserConfig } from 'hardhat/config'
import '@nomiclabs/hardhat-waffle'
import '@openzeppelin/hardhat-upgrades'

task('accounts', 'Prints the, list of accounts', async (args, hre) => {
  const accounts = await hre.ethers.getSigners()
  accounts.forEach((account) => console.log(account.address))
})

const config: HardhatUserConfig = {
  solidity: {
    version: '0.6.12',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  // networks: {
  //   hardhat: {
  //     forking: {
  //       url: 'https://eth-mainnet.alchemyapi.io/v2/TsLEJAhX87icgMO7ZVyPcpeEgpFEo96O',
  //       blockNumber: 11123663,
  //     },
  //   },
  // },
}

export default config
