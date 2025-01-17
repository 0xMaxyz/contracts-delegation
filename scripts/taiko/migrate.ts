
import { ethers } from "hardhat";
import {
    ConfigModule__factory,
    OneDeltaComposerTaiko__factory,
    LensModule__factory,
    ManagementModule__factory,
    OwnershipModule__factory,
} from "../../types";
import { getTaikoConfig } from "./utils";
import { OneDeltaTaiko } from "./addresses/oneDeltaAddresses";
import { getContractSelectors, ModuleConfigAction } from "../_utils/diamond";


async function main() {
    const accounts = await ethers.getSigners()
    const operator = accounts[1]
    const chainId = await operator.getChainId();

    // staging deployments
    const STAGE_IN = OneDeltaTaiko.STAGING
    const { proxy: stagingProxy, composerImplementation, ownershipImplementation, managementImplementation } = STAGE_IN

    // prod deployments
    const STAGE_OUT = OneDeltaTaiko.PRODUCTION
    const {
        proxy,
        composerImplementation: composerImplementationOld,
        managementImplementation: managementImplementationOld
    } = STAGE_OUT

    if (chainId !== 167000) throw new Error("invalid chainId")
    console.log("operator", operator.address, "on", chainId)

    // we manually increment the nonce
    let nonce = await operator.getTransactionCount()

    console.log("module deployed")

    const cut: {
        moduleAddress: string,
        action: any,
        functionSelectors: any[]
    }[] = []


    // get lens in prod to fetch modules
    const lens = await new LensModule__factory(operator).attach(proxy)

    /** REMOVALS */

    const composerSelectors = await lens.moduleFunctionSelectors(composerImplementationOld)
    const managementSelectors = await lens.moduleFunctionSelectors(managementImplementationOld)

    // remove old
    cut.push({
        moduleAddress: ethers.constants.AddressZero,
        action: ModuleConfigAction.Remove,
        functionSelectors: composerSelectors
    })
    cut.push({
        moduleAddress: ethers.constants.AddressZero,
        action: ModuleConfigAction.Remove,
        functionSelectors: managementSelectors
    })

    /** ADDITIONS */

    const stagingComposer = await new OneDeltaComposerTaiko__factory(operator).attach(stagingProxy)
    // add new
    cut.push({
        moduleAddress: composerImplementation,
        action: ModuleConfigAction.Add,
        functionSelectors: getContractSelectors(stagingComposer)
    })

    const stagingManagent = await new ManagementModule__factory(operator).attach(stagingProxy)
    cut.push({
        moduleAddress: managementImplementation,
        action: ModuleConfigAction.Add,
        functionSelectors: getContractSelectors(stagingManagent)
    })

    const stagingOwnership = await new OwnershipModule__factory(operator).attach(stagingProxy)
    cut.push({
        moduleAddress: ownershipImplementation,
        action: ModuleConfigAction.Add,
        functionSelectors: getContractSelectors(stagingOwnership)
    })

    // module config
    const oneDeltaModuleConfig = await new ConfigModule__factory(operator).attach(proxy)

    console.log("initiating upgrade")
    let tx = await oneDeltaModuleConfig.configureModules(cut, getTaikoConfig(nonce++))
    await tx.wait()
    console.log("modules added")

    console.log("upgrade complete")
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
