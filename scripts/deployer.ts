import {
    AppBuildsPluginV1,
    AppDistributionPluginV1,
    AppOwnerPluginV1,
    AssetlinksOracle,
    ContractStorage,
    PublisherGreenfieldPluginV1,
    OpenStore,
    OpenStoreRequestHandlerV1,
    PublisherAccountAppsPluginV1,
    PublisherAccountFactory,
    TrustedMulticall
} from "../typechain-types";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {OpenStoreConfigStruct} from "../typechain-types/contracts/store/OpenStore";
import {attachOrDeployMulticallContract0age, attachOrDeployMulticastContract} from "../test/utils/multicall";
import {deployContract, obtainSelectors, Selector, selectors} from "../test/utils/contracts";
import {BaseContract, id} from "ethers";
import {GfContracts, StoreConfig} from "./models";
import {CoreManager} from "./manager";
import {verbose} from "../test/utils/logger";
import {Defaults} from "./defaults";

export interface CoreContracts {
    multicall: TrustedMulticall
    storage: ContractStorage
    oracle: AssetlinksOracle
    factory: PublisherAccountFactory
    store: OpenStore

    multicallAddress: string
    storageAddress: string
    oracleAddress: string
    factoryAddress: string
    storeAddress: string
}

export interface AppPluginContracts {
    builds: AppBuildsPluginV1
    owner: AppOwnerPluginV1
    distribution: AppDistributionPluginV1
}

export interface DevPluginContracts {
    apps: PublisherAccountAppsPluginV1
    gf: PublisherGreenfieldPluginV1
}

interface CorePlugins {
    app: AppPlugins,
    dev: DevPlugins,
}

interface AppPlugins {
    builds: ContractPlugin<AppBuildsPluginV1>,
    owner: ContractPlugin<AppOwnerPluginV1>,
    distribution: ContractPlugin<AppDistributionPluginV1>,
}

interface DevPlugins {
    apps: ContractPlugin<PublisherAccountAppsPluginV1>,
    gf: ContractPlugin<PublisherGreenfieldPluginV1>,
}

export interface ContractPlugin<T extends BaseContract> {
    address: string,
    selectors: string[],
    contract: T,
}

export class ContractsDeployer {

    private _multicall?: TrustedMulticall
    private _storage?: ContractStorage
    private _oracle?: AssetlinksOracle
    private _factory?: PublisherAccountFactory
    private _store?: OpenStore

    private _multicallAddress?: string
    private _storageAddress?: string
    private _oracleAddress?: string
    private _factoryAddress?: string
    private _storeAddress?: string

    private _appPlugins?: AppPlugins
    private _devPlugins?: DevPlugins

    constructor(
        readonly admin: HardhatEthersSigner,
        readonly config: StoreConfig,
        readonly gfContracts: GfContracts,
        readonly oracleVerificationAmount: bigint,
        readonly isLocal: boolean = true,
    ) {}

    async deployAndSetupAll() {
        await this.deployMulticall()
        await this.deployAfterMulticall()
    }

    async deployAfterMulticall() {
        await this.deployContractsStorage()
        await this.deployDevFactory(this.storageAddress)

        await this.deployAssetlinksOracle(this.oracleVerificationAmount)
        await this.deployStore(this.oracleAddress)

        await this.deployAppPlugins()
        await this.deployDevPlugin(this.storageAddress)

        await this.setupContractsStorage(this.corePlugins)
    }

    async deployMulticall() {
        let multicall

        if (this.isLocal) {
            multicall = await attachOrDeployMulticastContract(this.admin)
        } else {
            multicall = await attachOrDeployMulticallContract0age(this.admin)
        }

        this._multicall = multicall
        this._multicallAddress = await multicall.getAddress()
        return multicall
    }

    async deployAssetlinksOracle(verificationAmount: bigint) {
        if (this._oracle) {
            throw Error("Oracle is already deployed!")
        }
        
        verbose("Deploying oracle with verification amount: ", verificationAmount)
        const oracle = await deployContract<AssetlinksOracle>(
            "AssetlinksOracle", [verificationAmount], this.admin
        )
        const oracleAddress = await oracle.getAddress()
        verbose(`Oracle address: ${oracleAddress}`)

        this._oracle = oracle
        this._oracleAddress = oracleAddress
        return oracle
    }

    async deployContractsStorage() {
        if (this._storage) {
            throw Error("Storage is already deployed!")
        }

        verbose("Deploying storage contract")
        const storage = await deployContract<ContractStorage>(
            "ContractStorage", [], this.admin
        )
        const storageAddress = await storage.getAddress()
        verbose(`Storage contract: ${storageAddress}`)

        this._storage = storage
        this._storageAddress = storageAddress
        return storage
    }

    async setupContractsStorage(plugins: CorePlugins) {
        // Set up App plugins
        verbose("Setting up App plugins")
        await this.storage.setDefaultPluginsForId(
            id(Defaults.Ids.APP_PLUGINS),
            [
                plugins.app.owner.address,
                plugins.app.builds.address,
                plugins.app.distribution.address
            ],
            ["0x", "0x", "0x"],
            [
                plugins.app.owner.selectors,
                plugins.app.builds.selectors,
                plugins.app.distribution.selectors,
            ]
        );

        // Set up PublisherAccount plugins
        verbose("Setting up PublisherAccount plugins")
        await this.storage.setDefaultPluginsForId(
            id(Defaults.Ids.PUBLISHER_PLUGINS),
            [
                plugins.dev.apps.address,
                plugins.dev.gf.address
            ],
            ["0x", "0x"],
            [
                plugins.dev.apps.selectors,
                plugins.dev.gf.selectors,
            ]
        );
    }

    async deployDevFactory(storageAddress: string) {
        if (this._factory) {
            throw Error("Factory is already deployed!")
        }

        verbose("Deploying factory contract")
        const factory = await deployContract<PublisherAccountFactory>(
            "PublisherAccountFactory", [storageAddress], this.admin,
        )
        const factoryAddress = await factory.getAddress()
        verbose(`Factory contract: ${factoryAddress}`)

        this._factory = factory
        this._factoryAddress = factoryAddress
        return factory
    }

    async deployStore(oracleAddress: string) {
        if (this._store) {
            throw Error("Store is already deployed!")
        }

        verbose("Deploying store contract")
        const requestHandler = await deployContract<OpenStoreRequestHandlerV1>(
            "OpenStoreRequestHandlerV1", [], this.admin
        )
        const handlerAddr = await requestHandler.getAddress()
        verbose(`Request handler contract: ${handlerAddr}`)

        const config = {
            ...this.config,
            oracle: oracleAddress,
            requestHandler: handlerAddr
        } as OpenStoreConfigStruct
        const store = await deployContract<OpenStore>(
            "OpenStore",
            [this.admin.address, config],
            this.admin
        )
        const storeAddress = await store.getAddress()
        verbose(`Store contract: ${storeAddress}`)

        this._store = store
        this._storeAddress = storeAddress
        return store
    }

    async deployAppPlugins() {
        if (this._appPlugins) {
            throw Error("App plugins are already deployed!")
        }

        const appOwnerV1 = await deployContract<AppOwnerPluginV1>("AppOwnerPluginV1", [], this.admin)
        const appOwnerAddress = await appOwnerV1.getAddress()
        const appOwnerSelectors = await obtainSelectors(appOwnerV1)

        const appBuildsV1 = await deployContract<AppBuildsPluginV1>("AppBuildsPluginV1", [], this.admin)
        const appBuildsAddress = await appBuildsV1.getAddress()
        const appBuildsSelectors = await obtainSelectors(appBuildsV1)

        const appDistributionV1 = await deployContract<AppDistributionPluginV1>("AppDistributionPluginV1", [], this.admin)
        const appDistributionAddress = await appDistributionV1.getAddress()
        const appDistributionSelectors = await obtainSelectors(appDistributionV1)

        this.printPlugin("Owner", appOwnerAddress, appOwnerSelectors)
        this.printPlugin("Build", appBuildsAddress, appBuildsSelectors)
        this.printPlugin("Distribution", appDistributionAddress, appDistributionSelectors)

        const _ownerSelectors = [
            "getState",
            "setAppOwner",
            "ownerVersion",
            "domain",
        ];
        const _buildSelectors = [
            "addBuild",
            "getBuild",
            "getLastVersionCode",
            "hasBuild",
        ];
        const _distributionSelectors = [
            "getDistribution",
            "getSource",
            "setDistribution",
        ];

        this._appPlugins = {
            owner: {
                address: appOwnerAddress,
                selectors: selectors(appOwnerSelectors, _ownerSelectors),
                contract: appOwnerV1,
            },
            builds: {
                address: appBuildsAddress,
                selectors: selectors(appBuildsSelectors, _buildSelectors),
                contract: appBuildsV1,
            },
            distribution: {
                address: appDistributionAddress,
                selectors: selectors(appDistributionSelectors, _distributionSelectors),
                contract: appDistributionV1,
            },
        }
    }

    async deployDevPlugin(storageAddress: string) {
        if (this._devPlugins) {
            throw Error("Dev plugins are already deployed!")
        }

        const devPluginApps = await deployContract<PublisherAccountAppsPluginV1>(
            "PublisherAccountAppsPluginV1",
            [storageAddress],
            this.admin
        )
        const devPluginAddress = await devPluginApps.getAddress()
        const devPluginSelector = await obtainSelectors(devPluginApps)

        const devPluginGf = await deployContract<PublisherGreenfieldPluginV1>(
            "PublisherGreenfieldPluginV1",
            [
                this.gfContracts.executor,
                this.gfContracts.permissionHub,
                this.gfContracts.tokenHub,
                this.gfContracts.bucketHub,
            ],
            this.admin
        )
        const devPluginGfAddress = await devPluginGf.getAddress()
        const devPluginGfSelectors = await obtainSelectors(devPluginGf)

        this.printPlugin("DevApps", devPluginAddress, devPluginSelector)
        this.printPlugin("Greenfield", devPluginGfAddress, devPluginGfSelectors)

        // TODO implement functionality to enable Transfer functions: approveAppTransfer
        const _appsSelectors = [
            "createApp",
            "getAppById",
            "computeAppAddress",
            "acceptAppTransfer",
        ];
        const _gfSelectors = [
            "topUp",
            "executeMsg",
            "createSpace",
            "changePolicy",
        ];

        this._devPlugins = {
            apps: {
                address: devPluginAddress,
                selectors: selectors(devPluginSelector, _appsSelectors),
                contract: devPluginApps,
            },
            gf: {
                address: devPluginGfAddress,
                selectors: selectors(devPluginGfSelectors, _gfSelectors),
                contract: devPluginGf,
            },
        }
    }

    get coreManager(): CoreManager {
        return new CoreManager(
            this.coreContracts,
            {
                apps: this.devPlugins.apps.contract,
                gf: this.devPlugins.gf.contract,
            },
            {
                builds: this.appPlugins.builds.contract,
                owner: this.appPlugins.owner.contract,
                distribution: this.appPlugins.distribution.contract,
            },
            this.admin,
        )
    }

    get appPlugins(): AppPlugins {
        if (!this._appPlugins) {
            throw Error("App plugins are not deployed!")
        }

        return this._appPlugins
    }

    get devPlugins(): DevPlugins {
        if (!this._devPlugins) {
            throw Error("Dev plugins are not deployed!")
        }

        return this._devPlugins
    }

    get corePlugins(): CorePlugins {
        return {
            app: this.appPlugins,
            dev: this.devPlugins,
        }
    }

    get coreContracts(): CoreContracts {
        return {
            multicall: this.multicall,
            storage: this.storage,
            oracle: this.oracle,
            factory: this.factory,
            store: this.store,

            multicallAddress: this.multicallAddress,
            storageAddress: this.storageAddress,
            oracleAddress: this.oracleAddress,
            factoryAddress: this.factoryAddress,
            storeAddress: this.storeAddress,
        }
    }

    get multicallAddress() {
        if (!this._multicallAddress) {
            throw Error("Multicall is not deployed!")
        }

        return this._multicallAddress
    }

    get storageAddress() {
        if (!this._storageAddress) {
            throw Error("Storage is not deployed!")
        }

        return this._storageAddress
    }

    get oracleAddress() {
        if (!this._oracleAddress) {
            throw Error("Oracle is not deployed!")
        }

        return this._oracleAddress
    }

    get factoryAddress() {
        if (!this._factoryAddress) {
            throw Error("Factory is not deployed!")
        }

        return this._factoryAddress
    }

    get storeAddress() {
        if (!this._storeAddress) {
            throw Error("Store is not deployed!")
        }

        return this._storeAddress
    }

    get multicall() {
        if (!this._multicall) {
            throw Error("Multicall is not deployed!")
        }

        return this._multicall
    }

    get storage() {
        if (!this._storage) {
            throw Error("Storage is not deployed!")
        }

        return this._storage
    }

    get oracle() {
        if (!this._oracle) {
            throw Error("Oracle is not deployed!")
        }

        return this._oracle
    }

    get factory() {
        if (!this._factory) {
            throw Error("Factory is not deployed!")
        }

        return this._factory
    }

    get store() {
        if (!this._store) {
            throw Error("Store is not deployed!")
        }

        return this._store
    }

    private printPlugin(name: string, address: string, selectors: Selector[]) {
        verbose(
            `
------------------------------------------------------------
name: ${name}
address: ${address}
selectors: ${JSON.stringify(selectors)}
------------------------------------------------------------
        `.trim()
        )
    }
}
