import {ethers} from "hardhat";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {
    AppAsset,
    AppBuildsPluginV1,
    AppDistributionPluginV1,
    AppOwnerPluginV1,
    PublisherAccount,
    PublisherAccountAppsPluginV1,
    PublisherGreenfieldPluginV1,
} from "../typechain-types";
import {AppGeneralInfoStruct} from "../typechain-types/contracts/app/AppAsset";
import {attachContract, findEvent, spent, wait} from "../test/utils/contracts";
import {AppPluginContracts, CoreContracts, DevPluginContracts} from "./deployer";
import {BytesLike, ContractRunner, getBytes, sha256, toBeHex, toUtf8Bytes} from "ethers";
import {Defaults} from "./defaults";
import {BigNumberish} from "ethers/src.ts/utils/maths";
import {verbose} from "../test/utils/logger";
import {BlockRefStruct} from "../typechain-types/contracts/store/OpenStore";

export class CoreManager {

    constructor(
        readonly contracts: CoreContracts,
        readonly dev: DevPluginContracts,
        readonly app: AppPluginContracts,
        readonly admin: HardhatEthersSigner,
    ) {
    }

    async devManager(name: string, user: HardhatEthersSigner) {
        const result = await wait(this.factoryFor(user)["createAccount(string)"](name))
        const log = findEvent("PublisherAccountCreated", result?.logs)
        verbose("PublisherAccountCreated log: ", log)
        const devAddress = log!.args[1];

        const PublisherAccount = await attachContract<PublisherAccount>("PublisherAccount", devAddress, user)
        const PublisherAccountAddress = await PublisherAccount.getAddress()
        verbose("PublisherAccount address:", PublisherAccountAddress)

        return new DevManager(
            PublisherAccount,
            await this.attachDevPluginsTo(PublisherAccountAddress, user),
            user
        )
    }

    async attachDevPluginsTo(manager: string, runner: ContractRunner) {
        return {
            apps: await attachContract<PublisherAccountAppsPluginV1>("PublisherAccountAppsPluginV1", manager, runner),
            gf: await attachContract<PublisherGreenfieldPluginV1>("PublisherGreenfieldPluginV1", manager, runner),
        } as DevPluginContracts
    }

    async enqueueAssetLinkRequest(appAddr: string, user: HardhatEthersSigner) {
        const oracle = this.coreContractFor(user).oracle;

        verbose("Is last version verified: ", oracle.getLastVerifiedAssetVersion(appAddr))

        const result = await wait(
            oracle["enqueue(address)"](appAddr, {value: Defaults.OracleFee.LH})
        );

        verbose(result.logs)
    }

    async lastVerifiedAssetVersion(appAddr: string) {
        return await this.contracts.oracle.getLastVerifiedAssetVersion(appAddr)
    }

    async finishAssetLinkRequest(reqId: number, status: number = 1) {
        const result = await wait(
            this.contracts.oracle.finish(reqId, status)
        );

        verbose(result.logs)
    }

    async addToReleaseTrack(appAddr: string, version: number, user: HardhatEthersSigner) {
        const store = this.coreContractFor(user).store;

        const result = await wait(
            store["addBuildToTrack(address,uint256,uint256)"](appAddr, 1, version)
        );

        verbose("Transaction status: ", result.status)
    }

    async addAndroidValidationRequest(target: string, version: BigNumberish, ownerVersion: BigNumberish, trackId: number, user: HardhatEthersSigner) {
        const store = this.coreContractFor(user).store;

        const params = AppManager.encodeBuildData(BigInt(version), ownerVersion, trackId)
        verbose(`Encoded data: ${params}`)

        const result = await wait(store["addValidationRequest(uint256,address,bytes)"](
                1, target, params,
                {value: Defaults.StoreConfig.LH.validationRequestAmount}
            )
        )

        verbose(`Transaction addValidationRequest status: ${result?.status}, ${spent(result)}`)
    }

    async proposeAndFinalize() {
        const store = this.contracts.store
        let result = await wait(
            store.registerValidator(1)
        );

        verbose("Register transaction status: ", result.status)
        if (result.status !== 1) {
            return
        }

        result = await wait(
            store.assignBlockId(await store.nextBlockIdToPropose())
        );
        verbose("Assign transaction status: ", result.status)
        if (result.status !== 1) {
            return
        }

        const nextBlock = await store.nextBlockIdToPropose();
        const nextReq = await store.nextRequestIdToValidate();
        const block: BlockRefStruct = {
            id: nextBlock,
            fromRequestId: nextReq - BigInt(1),
            toRequestId: nextReq,
            result: 1,
            objectId: "0xFF",
            protocolId: 1,
            objectHash: sha256("0x"),
            blockMask: 0,
            createdBy: this.admin.address
        }

        result = await wait(store.proposeBlock(block));
        verbose("Propose transaction status: ", result.status)
        if (result.status !== 1) {
            return
        }

        result = await wait(store.finalizeBlock(nextBlock))
        verbose("Finalize transaction status: ", result.status)

        result = await wait(store.unregisterValidator())
        verbose("Unregister transaction status: ", result.status)

        verbose(result.logs)
    }

    coreContractFor(runner: ContractRunner): CoreContracts {
        return {
            multicall: this.multicallFor(runner),
            storage: this.storageFor(runner),
            oracle: this.oracleFor(runner),
            factory: this.factoryFor(runner),
            store: this.storeFor(runner),

            multicallAddress: this.contracts.multicallAddress,
            storageAddress: this.contracts.storageAddress,
            oracleAddress: this.contracts.oracleAddress,
            factoryAddress: this.contracts.factoryAddress,
            storeAddress: this.contracts.storeAddress,
        }
    }

    multicallFor(runner: ContractRunner) {
        return this.contracts.multicall.connect(runner)
    }

    storageFor(runner: ContractRunner) {
        return this.contracts.storage.connect(runner)
    }

    oracleFor(runner: ContractRunner) {
        return this.contracts.oracle.connect(runner)
    }

    factoryFor(runner: ContractRunner) {
        return this.contracts.factory.connect(runner)
    }

    storeFor(runner: ContractRunner) {
        return this.contracts.store.connect(runner)
    }
}

export class DevManager {

    constructor(
        readonly PublisherAccount: PublisherAccount,
        readonly devPlugins: DevPluginContracts,
        readonly user: HardhatEthersSigner,
    ) {}

    async address() {
        return await this.PublisherAccount.getAddress()
    }

    async createApp(
        generalInfo: AppGeneralInfoStruct,
        user: HardhatEthersSigner,
    ) {
        const result = await wait(
            this.devPlugins.apps["createApp(string,string,string,uint16,uint16,uint16)"](
                generalInfo.id, generalInfo.name, generalInfo.description,
                generalInfo.protocolId, generalInfo.platformId, generalInfo.categoryId,
            )
        )
        verbose(`Transaction status: ${result?.status}`);

        const log = findEvent("AppCreated", result?.logs)
        const appAddress = log!.args[0];
        verbose(`New app address: ${appAddress}`);

        const app = await attachContract<AppAsset>("AppAsset", appAddress, user)

        return new AppManager(
            app,
            await this.attachAppPluginsTo(await app.getAddress(), user),
            user,
        )
    }

    async attachAppPluginsTo(manager: string, runner: ContractRunner) {
        return {
            builds: await attachContract<AppBuildsPluginV1>("AppBuildsPluginV1", manager, runner),
            owner: await attachContract<AppOwnerPluginV1>("AppOwnerPluginV1", manager, runner),
            distribution: await attachContract<AppDistributionPluginV1>("AppDistributionPluginV1", manager, runner),
        } as AppPluginContracts
    }
}

export class AppManager {

    constructor(
        private readonly app: AppAsset,
        private readonly appPlugins: AppPluginContracts,
        private readonly user: HardhatEthersSigner,
    ) {}

    async domain() {
        return await this.appPlugins.owner["domain()"]()
    }

    async ownerVersion() {
        return await this.appPlugins.owner.ownerVersion()
    }

    async address() {
        return await this.app.getAddress()
    }

    async owner() {
        return await this.app.owner()
    }

    async generalInfo() {
        return await this.app.getGeneralInfo()
    }

    async updateDistribution(source: string) {
        const sampleDistribution = {
            typeId: 1,
            sources: [toUtf8Bytes(source),]
        };

        const result = await wait(
            this.appPlugins.distribution["setDistribution(uint16,bytes[])"](sampleDistribution.typeId, sampleDistribution.sources)
        )

        verbose(`Transaction updateDistribution status: ${result?.status}, ${spent(result)}`)
    }

    async updateAppOwner(domain: string, finger: BytesLike, proof: BytesLike) {
        const result = await wait(
            this.appPlugins.owner["setAppOwner(string,bytes32[],bytes[])"](
                domain,
                [getBytes(finger)],
                [getBytes(proof)],
            )
        );

        verbose(`Transaction updateAppOwner status: ${result?.status}, ${spent(result)}`)
    }

    async addBuild(
        versionCode: number = 1
    ) {
        const referenceId = "0x00000000000000000000000000000000000000000000000000000000001973b2"
        const checksum = "0xCEA56514B3DE4832173B162947896760EA42A45B567773A3D1C0F5F05587E9EF"
        const result = await wait(
            this.appPlugins.builds["addBuild((bytes,uint16,string,uint256,bytes32))"](
                {
                    referenceId: referenceId,
                    protocolId: 1,
                    versionName: "1.0.0",
                    versionCode: versionCode,
                    checksum: checksum,
                }
            )
        )

        verbose(`Transaction addBuild status: ${result?.status}, ${spent(result)}`)
    }

    static encodeBuildData(buildId: BigNumberish, syncId: BigNumberish, trackId: number): string {
        const buildIdBytes = toBeHex(buildId, 8);
        const syncIdBytes = toBeHex(syncId, 8);

        const encoder = new ethers.AbiCoder()
        return encoder.encode(
            ["uint256", "uint256", "uint256"],
            [buildIdBytes, syncIdBytes, trackId]
        );
    }
}
