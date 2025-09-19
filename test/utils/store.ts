import {BlockRefStruct} from "../../typechain-types/contracts/store/OpenStore";
import {BLOCK_MASK, BLOCK_RESULT_STATUS} from "./const";
import {expect} from "chai";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {createResultMask} from "./mask";
import {AssetlinksOracle, OpenStore} from "../../typechain-types";
import {BigNumberish, id} from "ethers";
import {AppManager, CoreManager} from "../../scripts/manager";
import {Defaults} from "../../scripts/defaults";

export interface BlockRef {
    id: BigNumberish;
    fromRequestId: BigNumberish;
    toRequestId: BigNumberish;
    result?: number;
    resultStatuses?: number[];
    objectId?: string;
    protocolId?: number;
    objectHash?: string;
    isDiscussion?: boolean;
    blockMask?: number;
    createdBy: string;
}

export function createBlockRef(params: BlockRef): BlockRefStruct {
    const requestCount = BigInt(params.toRequestId.toString()) - BigInt(params.fromRequestId.toString());

    if (requestCount > Defaults.StoreConfig.LH.maxReqPerBlock) {
        throw new Error(`Request count ${requestCount} exceeds maxReqPerBlock ${Defaults.StoreConfig.LH.maxReqPerBlock}`);
    }

    const defaultResult = params.result ?? createResultMask(requestCount, params.resultStatuses);

    return {
        id: params.id,
        fromRequestId: params.fromRequestId,
        toRequestId: params.toRequestId,
        result: defaultResult,
        objectId: params.objectId ?? "0x1234567890abcdef",
        protocolId: params.protocolId ?? 1,
        objectHash: params.objectHash ?? id(params.createdBy),
        blockMask: params.blockMask ?? (params.isDiscussion ? BLOCK_MASK.IS_DISCUSSION : 0),
        createdBy: params.createdBy
    };
}

export function createDefaultBlockRef(
    id: BigNumberish,
    from: BigNumberish,
    validator: HardhatEthersSigner,
    status?: number,
) {
    return createBlockRef({
        id: id,
        fromRequestId: from,
        toRequestId: BigInt(from.toString()) + 1n,
        resultStatuses: [status ?? BLOCK_RESULT_STATUS.SUCCESS],
        createdBy: validator.address
    })
}

export function createDiscussBlockRef(
    block: BlockRefStruct,
    validator: HardhatEthersSigner,
    status?: number,
) {
    return createBlockRef({
        id: block.id,
        fromRequestId: block.fromRequestId,
        toRequestId: block.toRequestId,
        isDiscussion: true,
        resultStatuses: [status ?? BLOCK_RESULT_STATUS.SUCCESS],
        createdBy: validator.address
    })
}

export class BuildHelper {
    private appManager: AppManager

    constructor(appManager: AppManager) {
        this.appManager = appManager;
    }

    async addBuild(versionCode: number) {
        await expect(this.appManager.addBuild(versionCode)).not.to.be.reverted;
    }

    get appBuilds() {
        return this.appManager["appPlugins"].builds;
    }
}

export class OwnerHelper {
    private appManager: AppManager

    constructor(appManager: AppManager) {
        this.appManager = appManager;
    }

    async updateOwner(domain: string, fingerprint: string, proof: string) {
        await expect(
            this.appManager.updateAppOwner(domain, fingerprint, proof)
        ).not.to.be.reverted;

        return await this.appOwner.ownerVersion()
    }

    get appOwner() {
        return this.appManager["appPlugins"].owner;
    }
}

export class OracleHelper {
    public oracle: AssetlinksOracle
    public ownerHelper: OwnerHelper

    constructor(oracle: AssetlinksOracle, ownerHelper: OwnerHelper) {
        this.oracle = oracle;
        this.ownerHelper = ownerHelper;
    }

    async updateOwnerAndVerify(domain?: string, fingerprint?: string, proof?: string) {
        const version = await this.ownerHelper.updateOwner(
            domain ?? "example.com",
            fingerprint ?? id("0xFF"),
            proof ?? "0xFF"
        );
        await this.verifyOwner(this.oracle);
        return version;
    }

    async verifyOwner(oracle: AssetlinksOracle, status: number = 1) {
        const reqId = await oracle.nextQueueRequestId();
        const verificationFee = await oracle.getVerificationAmount();

        await expect(oracle["enqueue(address)"](await this.ownerHelper.appOwner.getAddress(), { value: verificationFee }))
            .not.to.be.reverted;

        await expect(oracle.finish(reqId, status))
            .not.to.be.reverted;

        return reqId;
    }
}

export class StoreHelper {
    public storeUser: OpenStore
    public buildHelper: BuildHelper
    public ownerHelper: OwnerHelper

    constructor(storeUser: OpenStore, buildHelper: BuildHelper, ownerHelper: OwnerHelper) {
        this.storeUser = storeUser;
        this.buildHelper = buildHelper;
        this.ownerHelper = ownerHelper;
    }

    encodeBuildData(versionCode: BigNumberish, ownerVersion: BigNumberish, trackId: number): string {
        return AppManager.encodeBuildData(versionCode, ownerVersion, trackId);
    }

    async addBuildsAndRequest(versionCode: number, ownerVersion?: BigNumberish) {
        const reqId = await this.storeUser.nextRequestIdToValidate();

        await this.buildHelper.addBuild(versionCode);

        await expect(this.addLastValidationRequest(versionCode, ownerVersion))
            .not.to.be.reverted;

        return reqId;
    }

    async addLastValidationRequest(versionCode?: BigNumberish, ownerVersion?: BigNumberish, fee?: BigNumberish, trackId: number = 1) {
        const buildId = versionCode ?? await this.buildHelper.appBuilds.getLastVersionCode();
        const version = ownerVersion ?? await this.ownerHelper.appOwner.ownerVersion();

        expect(buildId).to.be.gt(0);

        const config = await this.storeUser.config();
        return await this.storeUser["addValidationRequest(uint256,address,bytes)"](
            1, await this.buildHelper.appBuilds.getAddress(), this.encodeBuildData(buildId, version, trackId),
            {value: fee ?? config.validationRequestAmount}
        );
    }
}

export function createStoreHelpers(core: CoreManager, appManager: AppManager, store: OpenStore): {
    buildHelper: BuildHelper,
    ownerHelper: OwnerHelper,
    oracleHelper: OracleHelper,
    storeHelper: StoreHelper
} {
    const buildHelper = new BuildHelper(appManager);
    const ownerHelper = new OwnerHelper(appManager);
    const oracleHelper = new OracleHelper(core.contracts.oracle, ownerHelper);
    const storeHelper = new StoreHelper(store, buildHelper, ownerHelper);

    return { buildHelper, ownerHelper, oracleHelper, storeHelper };
}
