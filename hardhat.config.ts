import {HardhatUserConfig} from "hardhat/config";
import * as dotenv from 'dotenv';
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import {ethers} from "ethers";

dotenv.config();

const pks = []
if (process.env.DEPLOY_PK && process.env.DEPLOY_ADDRESS) {
    pks.push(`0x${process.env.DEPLOY_PK}`);
}

const config: HardhatUserConfig = {
    networks: {
        bsc: {
            chainId: 56,
            url: process.env.DEPLOY_URL,
            accounts: [
                ...pks
            ],
        },
        bsctest: {
            chainId: 97,
            url: process.env.DEPLOY_URL,
            accounts: [
                ...pks
            ],
        },
        localhost: {
            url: "http://127.0.0.1:8545",
            accounts: [
                "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", // first hardhat account
                `0x${process.env.TEST_PK!!}`
            ],
        },
    },
    abiExporter: [
        {
            path: 'reports/abi',
            format: "json",
            // pretty: true,
        },
    ],
    gasReporter: {
        enabled: Boolean(process.env.REPORT_GAS) || false,
        outputFile: "reports/gas",
        coinmarketcap: process.env.CMC_API
    },
    solidity: {
        version: "0.8.21",
        settings: {
            viaIR: true,
            optimizer: {
                enabled: true,
                runs: 10,
            },
        },
    },
    etherscan: {
        apiKey: process.env.BSCSCAN_API // ETHER_SCAN_API
    }
};

export default config;

//   details: {
//     // The peephole optimizer is always on if no details are given,
//     // use details to switch it off.
//     peephole: true,
//     // The unused jumpdest remover is always on if no details are given,
//     // use details to switch it off.
//     jumpdestRemover: true,
//     // Sometimes re-orders literals in commutative operations.
//     orderLiterals: true,
//     // Removes duplicate code blocks
//     deduplicate: true,
//     // Common subexpression elimination, this is the most complicated step but
//     // can also provide the largest gain.
//     cse: true,
//     // Optimize representation of literal numbers and strings in code.
//     constantOptimizer: true,
//     // The new Yul optimizer. Mostly operates on the code of ABIEncoderV2
//     // and inline assembly.
//     // It is activated together with the global optimizer setting
//     // and can be deactivated here.
//     // Before Solidity 0.6.0 it had to be activated through this switch.
//     yul: true,
//     // Tuning options for the Yul optimizer.
//     yulDetails: {
//       // Improve allocation of stack slots for variables, can free up stack slots early.
//       // Activated by default if the Yul optimizer is activated.
//       stackAllocation: true,
//     }
//   }