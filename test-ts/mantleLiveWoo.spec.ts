import { impersonateAccount } from "@nomicfoundation/hardhat-network-helpers";
import { parseUnits } from "ethers/lib/utils";
import { AToken__factory, ConfigModule__factory, DeltaBrokerProxy, DeltaBrokerProxy__factory, DeltaFlashAggregatorMantle__factory, DeltaLendingInterfaceMantle__factory, LensModule__factory, ManagementModule__factory, StableDebtToken__factory, } from "../types";
import { lendleBrokerAddresses } from "../deploy/mantle_addresses";
import { DeltaFlashAggregatorMantleInterface } from "../types/DeltaFlashAggregatorMantle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { addressesLendleATokens, addressesLendleVTokens, addressesTokensMantle } from "../scripts/mantle/lendleAddresses";
import { encodeAggregatorPathEthers } from "./1delta/shared/aggregatorPath";
import { FeeAmount, MaxUint128 } from "./uniswap-v3/periphery/shared/constants";
import { ModuleConfigAction, getSelectors } from "./libraries/diamond";
import { DeltaLendingInterfaceMantleInterface } from "../types/DeltaLendingInterfaceMantle";
const { ethers } = require("hardhat");


// block: 20240225
const MANTLE_CHAIN_ID = 5000;
const trader0 = '0xaffe73AA5EBd0CD95D89ab9fa2512Fc9e2d3289b'
const admin = '0x999999833d965c275A2C102a4Ebf222ca938546f'

const weth = "0xdEAddEaDdeadDEadDEADDEAddEADDEAddead1111"
const usdc = "0x09Bc4E0D864854c6aFB6eB9A9cdF58aC190D0dF9"
const wmnt = "0x78c1b0c915c4faa5fffa6cabf0219da63d7f4cb8"
const usdt = "0x201EBa5CC46D216Ce6DC03F6a759e8E766e956aE"

const wooRouter = '0xd14a997308F9e7514a8FEA835064D596CDCaa99E'

const brokerProxy = lendleBrokerAddresses.BrokerProxy[MANTLE_CHAIN_ID]
const traderModule = lendleBrokerAddresses.MarginTraderModule[MANTLE_CHAIN_ID]
let multicaller: DeltaBrokerProxy
let flashAggregatorInterface: DeltaFlashAggregatorMantleInterface
let lendingInterfaceInterface: DeltaLendingInterfaceMantleInterface
let user: SignerWithAddress
let trader: SignerWithAddress
before(async function () {
    const [signer] = await ethers.getSigners();
    user = signer
    console.log("get aggregator")
    multicaller = await new DeltaBrokerProxy__factory(user).attach(brokerProxy)
    flashAggregatorInterface = DeltaFlashAggregatorMantle__factory.createInterface()
    lendingInterfaceInterface = DeltaLendingInterfaceMantle__factory.createInterface()

    console.log("deploy new aggregator")
    const newflashAggregator = await new DeltaFlashAggregatorMantle__factory(signer).deploy()
    await impersonateAccount(admin)
    const impersonatedSigner = await ethers.getSigner(admin);
    console.log(impersonatedSigner.address)

    const config = await new ConfigModule__factory(impersonatedSigner).attach(brokerProxy)
    const lens = await new LensModule__factory(impersonatedSigner).attach(brokerProxy)

    const selectors = await lens.moduleFunctionSelectors(traderModule)
    await config.configureModules([
        {
            moduleAddress: ethers.constants.AddressZero,
            action: ModuleConfigAction.Remove,
            functionSelectors: selectors
        },
        {
            moduleAddress: newflashAggregator.address,
            action: ModuleConfigAction.Add,
            functionSelectors: getSelectors(newflashAggregator)
        }
    ])
})

it("Deposit", async function () {
    const amount = parseUnits('5000.0', 18)
    const callWrap = lendingInterfaceInterface.encodeFunctionData('wrap',)
    const callDeposit = lendingInterfaceInterface.encodeFunctionData('deposit' as any, [wmnt, user.address])

    await multicaller.connect(user).multicall([
        callWrap,
        callDeposit
    ], { value: amount })
})

it("Opens exact in, Woo last", async function () {
    const amount = parseUnits('2.0', 6)

    const borrowToken = await new StableDebtToken__factory(user).attach(addressesLendleVTokens.USDC)
    await borrowToken.approveDelegation(multicaller.address, MaxUint128)
    // v3 single
    const path1 = encodeAggregatorPathEthers(
        [usdc, weth, wmnt],
        [500, 0],
        [6, 0],
        [1, 101], // Agni, Woo
        2
    )
    const callSwap = flashAggregatorInterface.encodeFunctionData('flashSwapExactIn', [amount, 0, path1])
    console.log("attempt swap")
    await multicaller.connect(user).multicall([
        callSwap
    ])

})

