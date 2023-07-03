import '@nomiclabs/hardhat-ethers'
import { ethers } from "hardhat";
import { ConfigModule__factory, DeltaBrokerProxy__factory } from '../../types'

async function main() {

    const accounts = await ethers.getSigners()
    const operator = accounts[0]
    const chainId = await operator.getChainId();
    console.log("Deploy Module Manager on", chainId, "by", operator.address)
    // deploy ConfigModule
    const confgModule = await new ConfigModule__factory(operator).deploy()
    await confgModule.deployed()

    console.log("deploy broker proxy")
    const proxy = await new DeltaBrokerProxy__factory(operator).deploy(operator.address, confgModule.address)
    await proxy.deployed()

    console.log('ModuleConfig:', confgModule.address)
    console.log('Proxy:', proxy.address)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });