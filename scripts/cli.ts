import {ethers} from "hardhat";
import {wait} from "../test/utils/contracts";
import {parseEther,} from "ethers";
import * as readline from 'readline/promises';
import {Client} from "@bnb-chain/greenfield-js-sdk";
import {ContractsDeployer} from "./deployer";
import {Defaults} from "./defaults";
import {AppManager, CoreManager, DevManager} from "./manager";

const input = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

const topUpAmount = ethers.parseEther("15");

// Incremental
async function cli() {
    console.log("Please enter command:")
    console.log("----------------------------------------")

    while (true) {
        try {
            const cmd = await input.question('')
            await handle(cmd)
        } catch (e: any) {
            console.error(e);
            break;
        }
    }
}

let core: CoreManager
let dev: DevManager
let app: AppManager

async function handle(cmd: string) {
    const provider = ethers.provider

    const adminSigner = await provider.getSigner("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266") // first hardhat address
    const userSigner = await provider.getSigner(process.env.TEST_ADDRESS!!)

    const deployer = new ContractsDeployer(
        adminSigner, Defaults.StoreConfig.LH, Defaults.GreenfieldContracts.BscTest, Defaults.OracleFee.LH, true
    )

    const cmds = cmd.toLowerCase().split(' ')
    switch (cmds[0]) {
        case 'c': // 'create_contracts':
            await deployer.deployAndSetupAll()
            core = deployer.coreManager

            const result = await wait(core.contracts.store.topUp({value: topUpAmount}))
            console.log(`Transaction topUp status: ${result?.status}`)

            const balance = await core.contracts.store.balance(adminSigner.address)
            console.log(`Validator balance: ${balance}`)

            await adminSigner.sendTransaction({to: userSigner.address, value: parseEther("100")})
            break;

        case 'd': // 'create_dev':
            dev = await core.devManager(
                cmds[1] || Defaults.UserContractData.devName,
                userSigner
            )
            break;

        case 'a': // 'create_app':
            if (!dev) {
                console.log('Please create dev account first!')
                break;
            }

            // app = await createApp(devPlugins.apps, userSigner,
            app = await dev.createApp(
                Defaults.UserContractData.AppInfo,
                userSigner
            )
            break;

        case 'o': // 'update_app_owner':
            if (!app) {
                console.log('Please create app first!')
                break;
            }

            await app.updateAppOwner(
                cmds[1] || Defaults.UserContractData.owner.domain,
                cmds[2] || Defaults.UserContractData.owner.fingerprint,
                cmds[3] || Defaults.UserContractData.owner.proof
            )
            break;

        case 'l': // 'add_distribution_sources'
            if (!app) {
                console.log('Please create app first!')
                break;
            }

            await app.updateDistribution(
                cmds[1] || Defaults.UserContractData.distribution.link
            )
            break;

        case 's': // 'add_sync_request':
            if (!core || !app) {
                console.log('Please create oracle and app first!')
                break;
            }

            await core.enqueueAssetLinkRequest(await app.address(), userSigner)
            break;

        case 'r': // 'add_validation_request':
            if (!core || !app) {
                console.log('Please create store and app first!')
                break;
            }

            if (!cmds[1]) {
                console.log('Please specify version code!')
            }

            const versionCode = Number(cmds[1])

            await app.addBuild(versionCode)
            const ownerVersion = await core.lastVerifiedAssetVersion(await app.address())
            await core.addAndroidValidationRequest(
                await app.address(), versionCode, ownerVersion, 1, userSigner
            )

            break;

        // BSC ONLY
        case 'h':
            console.log("NOT IMPLEMENTED!")
            break

        // DEBUG ONLY
        case 'vs': // 'verify_sync':
            if (!core) {
                console.log('Please create oracle and app first!')
                break;
            }

            if (!cmds[1]) {
                console.log('Please specify request id!')
                break;
            }

            const requestId = Number(cmds[1])
            await core.finishAssetLinkRequest(requestId, 1)

            break;

        case 't': // add to track
            if (!core || !app) {
                console.log('Please create store and app first!')
                break
            }

            if (!cmds[1]) {
                console.log('Please specify version code!')
            }

            const versionCode1 = Number(cmds[1])
            await core.addToReleaseTrack(await app.address(), versionCode1, userSigner)

            break;

        case 'vr': // 'validate_req':
            if (!core) {
                console.log('Please create store first!')
                break;
            }

            await core.proposeAndFinalize()
            break;

        case 'ps': // 'print_app_state':
            if (!core || !app) {
                console.log('Please create oracle and app first!')
                break
            }

            const version = await core.lastVerifiedAssetVersion(await app.address())
            console.log(`Request: ${version}`)
            break;

        case `exit`:
            input.close();
            break;

        default:
            console.log('Invalid cmd!');
    }

    console.log('Done');
    console.log('----------------------------------------')
}

cli().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
