// hardhat.config.ts

import 'dotenv/config';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-solhint';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-abi-exporter';
import 'hardhat-deploy';
import 'hardhat-deploy-ethers';
import 'hardhat-gas-reporter';
import 'hardhat-spdx-license-identifier';
import '@typechain/hardhat';
import 'hardhat-watcher';
import 'solidity-coverage';
import "hardhat-contract-sizer";
// import '@openzeppelin/hardhat-upgrades';
// import {accounts} from './utils/networks';

//import './tasks';
import * as dotenv from 'dotenv';

dotenv.config();

import { HardhatUserConfig } from 'hardhat/types';
import { removeConsoleLog } from 'hardhat-preprocessor';



const LOW_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.8.17',
  settings: {
    optimizer: {
      enabled: true,
      runs: 1_500,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const LOWEST_OPTIMIZER_COMPILER_SETTINGS = {
  version: '0.8.17',
  settings: {
    viaIR: true,
    optimizer: {
      enabled: true,
      runs: 1_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}


const pk1: string = process.env.PK_1 || '';
const pk2: string = process.env.PK_2 || '';
const pk3: string = process.env.PK_3 || '';
const pk4: string = process.env.PK_3 || '';
const pk5: string = process.env.PK_5 || '';
const pk6: string = process.env.PK_6 || '';

const accounts = [pk1, pk5, pk3, pk6]

const config: HardhatUserConfig = {
  abiExporter: {
    path: './abi',
    clear: false,
    flat: true,
    // only: [],
    // except: []
  },
  defaultNetwork: 'hardhat',
  etherscan: {
    customChains: [
      {
        network: "mantle",
        chainId: 5000,
        urls: {
          apiURL: "https://api.mantlescan.xyz/api",
          browserURL: "https://mantlescan.xyz/"
        }
      },
      {
        network: "taiko",
        chainId: 167000,
        urls: {
          apiURL: "https://api.taikoscan.io/api",
          browserURL: "https://taikoscan.io"
        }
      },
      {
        network: "hemi",
        chainId: 43111,
        urls: {
          apiURL: "https://explorer.hemi.xyz/api",
          browserURL: "https://explorer.hemi.xyz/"
        }
      },
      {
        network: "core",
        chainId: 1116,
        urls: {
          apiURL: "https://openapi.coredao.org/api",
          browserURL: "https://scan.coredao.org"
        }
      },
      {
        network: "blast",
        chainId: 81457,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/mainnet/evm/81457/etherscan",
          browserURL: "https://blastexplorer.io"
        }
      },
      {
        network: "linea",
        chainId: 59144,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/mainnet/evm/59144/etherscan",
          browserURL: "https://blastexplorer.io"
        }
      },
      {
        network: "metis",
        chainId: 1088,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/mainnet/evm/1088/etherscan",
          browserURL: "https://andromeda-explorer.metis.io"
        }
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org"
        }
      },
      {
        network: "sonic",
        chainId: 146,
        urls: {
          apiURL: "https://api.sonicscan.org/api",
          browserURL: "https://sonicscan.org"
        }
      },
      {
        network: "fantom",
        chainId: 250,
        urls: {
          apiURL: "https://api.ftmscan.org/api",
          browserURL: "https://ftmscan.org"
        }
      },
      {
        network: "scroll",
        chainId: 534352,
        urls: {
          apiURL: "https://api.scrollscan.com/api",
          browserURL: "https://scrollscan.com"
        }
      }
    ],
    apiKey: {
      mantle: process.env.MANTLESCAN_API_KEY ?? "abc",
      arbitrumOne: process.env.ARBISCAN_API_KEY ?? "",
      mainnet: process.env.ETHERSCAN_API_KEY ?? '',
      polygon: process.env.POLYGONSCAN_API_KEY ?? '',
      taiko: process.env.TAIKOSCAN_API_KEY ?? '',
      linea: process.env.LINEASCAN_API_KEY ?? '',
      optimisticEthereum: process.env.OPSCAN_API_KEY ?? '',
      bsc: process.env.BSCSCAN_API_KEY ?? '',
      gnosis: process.env.GNOSISSCAN_API_KEY ?? '',
      blast: process.env.BLASTSCAN_API_KEY ?? '',
      base: process.env.BASESCAN_API_KEY ?? '',
      metis: "XX",
      avalanche: "XX",
      hemi: "XX",
      core:  process.env.CORESCAN_API_KEY ?? '',
      sonic:  process.env.SONICSCAN_API_KEY ?? '',
      scroll:  process.env.SCROLLSCAN_API_KEY ?? '',
      fantom:  process.env.FANTOMSCAN_API_KEY ?? '',
    }
  },
  gasReporter: {
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    currency: 'USD',
    enabled: true,
    excludeContracts: ['contracts/mocks/', 'contracts/libraries/'],
  },
  mocha: {
    timeout: 500000,
  },
  networks: {
    mainnet: {
      url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts,
      chainId: 1,
    },
    localhost: {
      url: 'http://localhost:8545',
      live: false,
      accounts
    },
    hardhat: {
      mining: {
        // auto: false,
        // interval: 0
      },
      // allowUnlimitedContractSize: true,

      // forking: {
      //   blockNumber: 53244031,
      //   url: `https://rpc.ankr.com/polygon`,
      // },
      // forking:{
      //   blockNumber: 18748428,
      //   url: 'https://rpc.ankr.com/eth'
      // },
      forking: {
        blockNumber: 320071,
        url: `https://rpc.ankr.com/taiko`,
      },
      // forking: {
      //   blockNumber: 35180036,
      //   url: `https://rpc.ankr.com/bsc`,
      // },
    },
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts,
      chainId: 4,
      live: true,
    },
    taiko: {
      url: 'https://rpc.taiko.xyz',
      accounts,
      chainId: 167000,
    },
    moonbase: {
      url: 'https://rpc.testnet.moonbeam.network',
      accounts,
      chainId: 1287,
      live: true,
      gas: 5198000,
    },
    fantom: {
      url: 'https://rpcapi.fantom.network',
      accounts,
      chainId: 250,
      live: true,
    },
    hemi: {
      url: 'https://rpc.hemi.network/rpc',
      accounts,
      chainId: 43111,
      live: true,
    },
    core: {
      url: 'https://rpc.coredao.org',
      accounts,
      chainId: 1116,
      live: true,
    },
    scroll: {
      url: 'https://rpc.scroll.io',
      accounts,
      chainId: 534352,
      live: true,
    },
    sonic: {
      url: 'https://rpc.soniclabs.com',
      accounts,
      chainId: 146,
      live: true,
    },
    matic: {
      url: 'https://rpc.ankr.com/polygon',
      accounts,
      chainId: 137,
    },
    base: {
      url: 'https://mainnet.base.org',
      accounts,
      live: true,
    },
    mantle: {
      url: 'https://rpc.mantle.xyz',
      accounts,
      chainId: 5000,
    },
    xdai: {
      url: 'https://rpc.ankr.com/gnosis',
      accounts,
      chainId: 100,
      live: true,
    },
    bsc: {
      url: 'https://bsc-dataseed.binance.org',
      chainId: 56,
      live: true,
      accounts,
    },
    heco: {
      url: 'https://http-mainnet.hecochain.com',
      accounts,
      chainId: 128,
      live: true,
    },
    mode: {
      url: 'https://mainnet.mode.network',
      accounts,
      chainId: 34443,
      live: true,
    },
    avalanche: {
      url: 'https://avalanche.public-rpc.com',
      accounts,
      chainId: 43114,
      live: true,
    },
    harmony: {
      url: 'https://api.s0.t.hmny.io',
      accounts,
      chainId: 1666600000,
      live: true,
    },
    okex: {
      url: 'https://exchainrpc.okex.org',
      accounts,
      chainId: 66,
      live: true,
    },
    arbitrum: {
      url: 'https://arbitrum.drpc.org',
      chainId: 42161,
      live: true,
      blockGasLimit: 700000,
      accounts,
    },
    blast: {
      url: 'https://rpc.blast.io',
      live: true,
      accounts,
    },
    celo: {
      url: 'https://forno.celo.org',
      accounts,
      chainId: 42220,
      live: true,
    },
    metis: {
      url: 'https://metis-andromeda.rpc.thirdweb.com',
      accounts,
      chainId: 1088,
      live: true,
    },
    palm: {
      url: 'https://palm-mainnet.infura.io/v3/da5fbfafcca14b109e2665290681e267',
      accounts,
      chainId: 11297108109,
      live: true,
    },
    optimism: {
      url: "https://rpc.ankr.com/optimism",
      live: true,
      accounts,
    },
    linea: {
      url: "https://1rpc.io/linea",
      live: true,
      accounts,
    }
  },
  paths: {
    artifacts: 'artifacts',
    cache: 'cache',
    deploy: 'deploy',
    deployments: 'deployments',
    imports: 'imports',
    sources: 'contracts',
    tests: 'test/1delta',
  },
  preprocess: {
    eachLine: removeConsoleLog(
      (bre) =>
        bre.network.name !== 'hardhat' && bre.network.name !== 'localhost'
    ),
  },
  solidity: {
    compilers: [
      // 1delta
      {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000_000,
          },
          evmVersion: 'cancun',
        },
      },
      // uniswap
      {
        version: '0.6.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000_000,
          },
        },
      },
      {
        version: '0.7.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 800,
          },
          metadata: {
            // do not include the metadata hash, since this is machine dependent
            // and we want all generated code to be deterministic
            // https://docs.soliditylang.org/en/v0.7.6/metadata.html
            bytecodeHash: 'none',
          },
        },
      },
      // iZi
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100
          },
          outputSelection: {
            "*": {
              "*": [
                "abi",
                "evm.bytecode",
                "evm.deployedBytecode",
                "evm.methodIdentifiers",
                "metadata"
              ],
            }
          }
        }
      },

      // aave
      {
        version: '0.8.10',
        settings: {
          optimizer: {
            enabled: true,
            runs: 10_0000,
          },
          evmVersion: 'london',
        },
      },
      // Uniswap V2
      {
        version: '0.6.6',
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999,
          },
          evmVersion: 'istanbul',
        },
      },
      {
        version: '0.5.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 999999,
          },
          evmVersion: 'istanbul',
        },
      }
    ],
    overrides: {
      // proxy
      "contracts/1delta/proxy/DeltaBrokerGen2.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000_000,
          },
          evmVersion: 'cancun',
        },
      },
      // deploy factory
      "contracts/1delta/modules/shared/DeployFactory.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000_000,
          },
          evmVersion: 'paris',
        },
      },
      // ma
      "contracts/1delta/modules/shared/MetaAggregator.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000_000,
          },
          evmVersion: 'paris',
        },
      },
      // composers
      "contracts/1delta/modules/polygon/Composer.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 5_000,
          },
          evmVersion: 'cancun',
        },
      },
      "contracts/1delta/modules/arbitrum/Composer.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 500,
          },
          evmVersion: 'cancun',
        },
      },
      "contracts/1delta/modules/hemi/Composer.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000_000,
          },
          evmVersion: 'cancun',
        },
      },
      "contracts/1delta/modules/optimism/Composer.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 7_500,
          },
          evmVersion: 'cancun',
        },
      },
      "contracts/1delta/modules/base/Composer.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 750,
          },
          evmVersion: 'cancun',
        },
      },
      "contracts/1delta/modules/ethereum/Composer.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000,
          },
          evmVersion: 'cancun',
        },
      },
      "contracts/1delta/modules/mantle/Composer.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 10_000,
          },
          evmVersion: 'shanghai',
        },
      },
      "contracts/1delta/modules/taiko/Composer.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000_000,
          },
          evmVersion: 'shanghai',
        },
      },
      "contracts/1delta/quoter/MoeJoeLens.sol": {
        version: '0.8.28',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1_000_000,
          },
          evmVersion: 'paris',
        },
      },
      // periphery
      'contracts/external-protocols/algebra/periphery/NonfungiblePositionManager.sol': LOW_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/external-protocols/algebra/periphery/LimitOrderManager.sol': LOW_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/external-protocols/algebra/periphery/test/MockTimeNonfungiblePositionManager.sol': LOW_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/external-protocols/algebra/periphery/test/NFTDescriptorTest.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/external-protocols/algebra/periphery/NonfungibleTokenPositionDescriptor.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/external-protocols/algebra/periphery/libraries/NFTDescriptor.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
      'contracts/external-protocols/algebra/periphery/libraries/NFTSVG.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
    }
  },
  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },
  typechain: {
    outDir: 'types',
    target: 'ethers-v5',
  },
  watcher: {
    compile: {
      tasks: ['compile'],
      files: ['./src'],
      verbose: true,
    },
  },
  contractSizer: {
    runOnCompile: false,
    disambiguatePaths: false,
  },
};

export default config;
