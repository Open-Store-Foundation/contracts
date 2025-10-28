import {artifacts} from "hardhat";
import * as fs from "node:fs";
import { join } from "node:path";

async function main() {
    const contracts = [
        "AppAsset",
        "AppOwnerPluginV1",
        "AppBuildsPluginV1",
        "PublisherAccountFactory",
        "PublisherAccount",
        "PublisherAccountAppsPluginV1",
        "AppDistributionPluginV1",
        "PublisherGreenfieldPluginV1",
        "AssetlinksOracle",
        "OpenStoreV1",
        "OpenStoreV0",
        "TrustedMulticall",
    ]

    const jsonDirs = process.env["CONTRACTS_JSON_DIRS"]
        ?.split(":")
    console.log("ABI for jsonDirs: ", jsonDirs)

    const tsDirs = process.env["CONTRACT_TS_DIRS"]
        ?.split(":")
    console.log("ABI for tsDirs: ", tsDirs)

    for (const name of contracts) {
        const contract = await artifacts.readArtifact(name)
        const abiString = JSON.stringify(contract.abi, null, 2);

        if (jsonDirs) {
            for (const jsonDir of jsonDirs) {
                const path = join(jsonDir, `${name}.json`)
                fs.writeFileSync(path, abiString)
            }
        }

        if (tsDirs) {
            for (const tsDir of tsDirs) {
                const path = join(tsDir, `${name}.ts`)
                fs.writeFileSync(path, `export const ${name}Abi = ${abiString}`)
            }
        }

        console.log(`Contract "${name}" is exported!`)
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
