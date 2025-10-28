import {ContractsFactory, TrustedMulticall} from "../../typechain-types";
import {ethers} from "hardhat";
import {attachContract, deployContract, wait} from "./contracts";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {toBeHex} from "ethers";

export const EXPECTED_MULTICALL_TESTNET_ADDRESS = "0x3f7AdDD276bC5c1a2Fffb329DD718f1fa0625D84"
export const EXPECTED_MULTICAST_LH_ADDRESS = "0x8d90514875B0920FCEb79464045aB56A8aAa3f6B"
const expectedAddress = EXPECTED_MULTICALL_TESTNET_ADDRESS

export async function attachOrDeployMulticallContract0age(admin: HardhatEthersSigner): Promise<TrustedMulticall> {
    const factoryAddress = "0x0000000000FFe8B47B3e2130213B802212439497"

    const provider = ethers.provider

    if (expectedAddress === undefined || await provider.getCode(expectedAddress) == "0x") {
        const factory = await ethers.getContractFactory("TrustedMulticall")
        const salt = toBeHex(1, 32)

        const factoryAbi = [
            "function findCreate2Address(bytes32 salt, bytes calldata initCode) external view returns (address)",
            "function safeCreate2(bytes32 salt, bytes calldata initializationCode) external payable returns (address)"
        ];

        const factoryContract = new ethers.Contract(factoryAddress, factoryAbi, admin);
        const predictedAddress = await factoryContract.findCreate2Address(
            salt,
            factory.bytecode
        );

        if (expectedAddress !== undefined && predictedAddress != expectedAddress) {
            throw new Error(`Multicall address is not correct: Actual - ${factoryContract} | Expected - ${expectedAddress}`)
        }

        const result = await wait(
            factoryContract.safeCreate2(
                salt,
                factory.bytecode
            )
        );

        if (result.status != 1) {
            throw new Error(`Multicall deployment failed: ${result.status}`)
        } else {
            console.log("Multicall contract deployed with address: ", predictedAddress)
        }

        return await attachContract<TrustedMulticall>("TrustedMulticall", predictedAddress, admin)
    } else {
        return await attachContract<TrustedMulticall>("TrustedMulticall", expectedAddress, admin)
    }
}

export async function attachOrDeployMulticastContract(admin: HardhatEthersSigner): Promise<TrustedMulticall> {
    if (await ethers.provider.getCode(expectedAddress) == "0x") {
        console.log("Multicall contract not deployed yet")

        const contractsFactory = await deployContract<ContractsFactory>("ContractsFactory", [admin.address], admin)
        console.log("ContractsFactory address:", await contractsFactory.getAddress())

        const contract = await contractsFactory.multicallAddress(0)
        if (contract != expectedAddress) {
            throw new Error(`Multicall address is not correct: Actual - ${contract} | Expected - ${expectedAddress}`)
        }

        await wait(contractsFactory.createMulticall(0))

        const multicall = await attachContract<TrustedMulticall>(
            "TrustedMulticall", await contractsFactory.multicallAddress(0), admin
        )

        const address = await multicall.getAddress();
        if (address != expectedAddress) {
            throw new Error(`Multicall address is not correct: Actual - ${address} | Expected - ${expectedAddress}`)
        }

        console.log("TrustedMulticall address:", expectedAddress)

        return multicall
    } else {
        return await attachContract<TrustedMulticall>("TrustedMulticall", expectedAddress, admin)
    }
}
