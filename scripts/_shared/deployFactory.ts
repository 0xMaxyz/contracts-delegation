
import { ethers } from "hardhat";
import { DeployFactory__factory } from "../../types";

// deployed on
// avalanche
// mantle
// base
// polygon
// arbitrum
// blast
// linea
// optimism
// bnb chain
// taiko
// xdai
// metis
// mode
// hemi
// core
// sonic
// fantom
// scroll

async function main() {
    const accounts = await ethers.getSigners()
    const operator = accounts[3]
    const chainId = await operator.getChainId();
    console.log("operator", operator.address, "on", chainId)

    console.log("Deploy factory")
    const deployFactory = await new DeployFactory__factory(operator).deploy()

    await deployFactory.deployed()

    console.log("factory:", deployFactory.address)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
