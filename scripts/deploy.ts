import {ContractsDeployer} from "./deployer";
import {ethers} from "hardhat";
import {Defaults} from "./defaults";
import {attachOrDeployMulticallContract0age, EXPECTED_MULTICALL_TESTNET_ADDRESS} from "../test/utils/multicall";
import * as fs from "node:fs";

// 0. Check admin has enough balance to deploy contracts
// 1. Call preDeploy
// 2. Replace hardcoded addresses with actual ones in Trustable.sol
// 3. Call deploy
async function preDeploy() {
    const adminAddress = process.env["DEPLOY_ADDRESS"]
    console.log("Deploying multicall contract...")
    const provider = ethers.provider

    const adminSigner = await provider.getSigner(adminAddress)
    await attachOrDeployMulticallContract0age(adminSigner)

    console.log("Deploying multicall contract... DONE")
}

async function deploy() {
    const adminAddress = process.env["DEPLOY_ADDRESS"]

    console.log("Deploying base contracts...")
    const content = fs.readFileSync(`${process.env.PWD}/contracts/multicall/Trustable.sol`, 'utf8')
    if (content.search(EXPECTED_MULTICALL_TESTNET_ADDRESS) == 0) {
        throw new Error(`Multicall address is not correct: Expected - ${EXPECTED_MULTICALL_TESTNET_ADDRESS}`)
    }

    const provider = ethers.provider
    const adminSigner = await provider.getSigner(adminAddress)

    let deployer = new ContractsDeployer(
        adminSigner,
        Defaults.StoreConfig.BscTest,
        Defaults.GreenfieldContracts.BscTest,
        Defaults.OracleFee.BscTest,
        true,
        false
    )

    await deployer.deployAndSetupAll()
    console.log("Deploying base contracts... DONE")
}

if (require.main === module) {
    // preDeploy().then(() => process.exit(0))
    deploy().then(() => process.exit(0))
}