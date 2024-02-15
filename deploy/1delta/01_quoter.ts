import '@nomiclabs/hardhat-ethers'
import { ethers } from "hardhat";
import { OneDeltaQuoterMantle__factory } from '../../types'

async function main() {

    const accounts = await ethers.getSigners()
    const operator = accounts[1]
    const chainId = await operator.getChainId();
    console.log("Deploy Module Manager on", chainId, "by", operator.address)


    console.log("deploy quoter on mantle")

    const deploymentData = await new OneDeltaQuoterMantle__factory(operator).getDeployTransaction()
    const estimatedGas = await ethers.provider.estimateGas({ data: deploymentData.data });

    console.log("EST GAS", estimatedGas.toString())
    const quoter = await new OneDeltaQuoterMantle__factory(operator).deploy({ gasLimit: estimatedGas.mul(105).div(100) })
    await quoter.deployed()

    console.log('quoter:', quoter.address) // 0xee3a775E5F5C4E8e252C6510F152C80F283eEb90
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });