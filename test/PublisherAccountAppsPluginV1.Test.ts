import {expect} from "chai";
import {ethers} from "hardhat";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {attachContract, getFactory, findEvent, wait} from "./utils/contracts";
import {PublisherAccountAppsPluginV1} from "../typechain-types";
import {id, parseEther} from "ethers";
import {ContractsDeployer} from "../scripts/deployer";
import {Defaults} from "../scripts/defaults";
import {CoreManager, DevManager} from "../scripts/manager";
import {attachOrDeployMulticastContract} from "./utils/multicall";
import {App} from "@bnb-chain/greenfield-cosmos-types/tendermint/version/types";
import {disableLogging} from "./utils/logger";

describe("PublisherAccountAppsPluginV1", function () {
    let deployer: ContractsDeployer;
    let core: CoreManager;
    let devManager: DevManager;
    let plugin: PublisherAccountAppsPluginV1;
    let admin: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;

    const sampleAppData = {
        id: "com.example.app",
        name: "Test App",
        description: "A test application",
        protocolId: 1,
        platformId: 1,
        categoryId: 2
    };

    beforeEach(async function () {
        disableLogging();

        [admin, user1, user2] = await ethers.getSigners();
        await attachOrDeployMulticastContract(admin);

        await admin.sendTransaction({to: user1.address, value: parseEther("10")});
        await admin.sendTransaction({to: user2.address, value: parseEther("10")});

        deployer = new ContractsDeployer(
            admin,
            Defaults.StoreConfig.LH,
            Defaults.GreenfieldContracts.BscTest,
            Defaults.OracleFee.LH
        );

        await deployer.deployAndSetupAll();
        core = deployer.coreManager;

        const topUpAmount = ethers.parseEther("15");
        const result = await wait(core.contracts.store.topUp({value: topUpAmount}));
        expect(result.status).to.equal(1);

        devManager = await core.devManager("TestDev", user1);
        plugin = devManager.devPlugins.apps;
    });

    describe("computeAppAddress", function () {
        it("should compute app address correctly", async function () {
            const computedAddress = await plugin.computeAppAddress(
                sampleAppData.id,
                sampleAppData.name,
                sampleAppData.description,
                sampleAppData.protocolId,
                sampleAppData.platformId,
                sampleAppData.categoryId
            );

            expect(computedAddress).to.be.properAddress;
            expect(computedAddress).to.not.equal(ethers.ZeroAddress);
        });

        it("should return same address for same parameters", async function () {
            const address1 = await plugin.computeAppAddress(
                sampleAppData.id,
                sampleAppData.name,
                sampleAppData.description,
                sampleAppData.protocolId,
                sampleAppData.platformId,
                sampleAppData.categoryId
            );

            const address2 = await plugin.computeAppAddress(
                sampleAppData.id,
                sampleAppData.name,
                sampleAppData.description,
                sampleAppData.protocolId,
                sampleAppData.platformId,
                sampleAppData.categoryId
            );

            expect(address1).to.equal(address2);
        });

        it("should return different addresses for different packages", async function () {
            const address1 = await plugin.computeAppAddress(
                "com.example.app1",
                sampleAppData.name,
                sampleAppData.description,
                sampleAppData.protocolId,
                sampleAppData.platformId,
                sampleAppData.categoryId
            );

            const address2 = await plugin.computeAppAddress(
                "com.example.app2",
                sampleAppData.name,
                sampleAppData.description,
                sampleAppData.protocolId,
                sampleAppData.platformId,
                sampleAppData.categoryId
            );

            expect(address1).to.not.equal(address2);
        });

        it("should handle empty strings", async function () {
            const computedAddress = await plugin.computeAppAddress(
                "",
                "",
                "",
                0,
                0,
                0
            );

            expect(computedAddress).to.be.properAddress;
            expect(computedAddress).to.not.equal(ethers.ZeroAddress);
        });

        it("should handle unicode characters", async function () {
            const computedAddress = await plugin.computeAppAddress(
                "com.测试.应用",
                "テストアプリ🚀",
                "测试应用描述",
                1,
                1,
                2
            );

            expect(computedAddress).to.be.properAddress;
            expect(computedAddress).to.not.equal(ethers.ZeroAddress);
        });
    });

    describe("createApp (via DevManager)", function () {
        it("should create app successfully", async function () {
            const appManager = await devManager.createApp(sampleAppData, user1);

            expect(appManager).to.not.be.undefined;
            const appAddress = await appManager.address();
            expect(appAddress).to.be.properAddress;
            expect(appAddress).to.not.equal(ethers.ZeroAddress);
        });

        it("should create app at computed address", async function () {
            const computedAddress = await plugin.computeAppAddress(
                sampleAppData.id,
                sampleAppData.name,
                sampleAppData.description,
                sampleAppData.protocolId,
                sampleAppData.platformId,
                sampleAppData.categoryId
            );

            const appManager = await devManager.createApp(sampleAppData, user1);
            const actualAddress = await appManager.address();

            expect(actualAddress).to.equal(computedAddress);
        });

        it("should create valid App contract", async function () {
            const appManager = await devManager.createApp(sampleAppData, user1);
            const general = await appManager.generalInfo()

            expect(general.id).to.equal(sampleAppData.id);
            expect(general.name).to.equal(sampleAppData.name);
            expect(general.description).to.equal(sampleAppData.description);
            expect(general.protocolId).to.equal(sampleAppData.protocolId);
            expect(general.platformId).to.equal(sampleAppData.platformId);
            expect(general.categoryId).to.equal(sampleAppData.categoryId);
            expect(await appManager.delegateOwner()).to.be.equal(user1.address);
        });

        it("should revert when creating duplicate app", async function () {
            await devManager.createApp(sampleAppData, user1);

            await expect(
                plugin["createApp(string,string,string,uint16,uint16,uint16)"](
                    sampleAppData.id,
                    "Different Name",
                    "Different Description",
                    99,
                    99,
                    99
                )
            ).to.be.revertedWithCustomError(plugin, "PublisherAccountAppsPluginError")
                .withArgs(1);
        });

        it("should revert when called by non-owner", async function () {
            const devManager2 = await core.devManager("TestDev2", user2);
            const plugin2 = devManager2["devPlugins"].apps.connect(user1);

            await expect(
                plugin2["createApp(string,string,string,uint16,uint16,uint16)"](
                    sampleAppData.id,
                    sampleAppData.name,
                    sampleAppData.description,
                    sampleAppData.protocolId,
                    sampleAppData.platformId,
                    sampleAppData.categoryId
                )
            ).to.be.revertedWithCustomError(plugin2, "OwnableUnauthorizedAccount")
                .withArgs(user1.address);
        });

        it("should create multiple apps with different packages", async function () {
            const apps = [
                {...sampleAppData, id: "com.example.app1"},
                {...sampleAppData, id: "com.example.app2"},
                {...sampleAppData, id: "com.example.app3"}
            ];

            const addresses: string[] = [];

            for (const appData of apps) {
                const appManager = await devManager.createApp(appData, user1);
                const address = await appManager.address();
                addresses.push(address);
            }

            expect(addresses.length).to.equal(3);
            expect(new Set(addresses).size).to.equal(3);
        });
    });

    describe("createApp (direct call)", function () {
        it("should create app successfully", async function () {
            const tx = await plugin["createApp(string,string,string,uint16,uint16,uint16)"](
                sampleAppData.id,
                sampleAppData.name,
                sampleAppData.description,
                sampleAppData.protocolId,
                sampleAppData.platformId,
                sampleAppData.categoryId
            );

            const receipt = await wait(Promise.resolve(tx));
            expect(receipt.status).to.equal(1);

            const event = findEvent("AppCreated", receipt.logs);
            expect(event).to.not.be.null;
            expect(event!.args[1]).to.equal(sampleAppData.id);
            expect(event!.args[2]).to.equal(sampleAppData.name);

            const appAddress = event!.args[0];
            expect(appAddress).to.be.properAddress;
            expect(appAddress).to.not.equal(ethers.ZeroAddress);
        });
    });

    describe("getAppById", function () {
        it("should return correct app address for existing package", async function () {
            const appManager = await devManager.createApp(sampleAppData, user1);
            const expectedAddress = await appManager.address();

            const retrievedAddress = await plugin.getAppById(sampleAppData.id);
            expect(retrievedAddress).to.equal(expectedAddress);
        });

        it("should return zero address for non-existent package", async function () {
            const retrievedAddress = await plugin.getAppById("com.nonexistent.app");
            expect(retrievedAddress).to.equal(ethers.ZeroAddress);
        });

        it("should return different addresses for different packages", async function () {
            const app1Data = {...sampleAppData, id: "com.example.app1"};
            const app2Data = {...sampleAppData, id: "com.example.app2"};

            const appManager1 = await devManager.createApp(app1Data, user1);
            const appManager2 = await devManager.createApp(app2Data, user1);

            const address1 = await plugin.getAppById(app1Data.id);
            const address2 = await plugin.getAppById(app2Data.id);

            expect(address1).to.not.equal(address2);
            expect(address1).to.not.equal(ethers.ZeroAddress);
            expect(address2).to.not.equal(ethers.ZeroAddress);

            expect(address1).to.equal(await appManager1.address());
            expect(address2).to.equal(await appManager2.address());
        });
    });

    describe("events", function () {
        it("should emit AppCreated event with correct parameters", async function () {
            await expect(
                plugin["createApp(string,string,string,uint16,uint16,uint16)"](
                    sampleAppData.id,
                    sampleAppData.name,
                    sampleAppData.description,
                    sampleAppData.protocolId,
                    sampleAppData.platformId,
                    sampleAppData.categoryId
                )
            ).to.emit(plugin, "AppCreated")
                .withArgs(
                    function (address: string) {
                        return address !== ethers.ZeroAddress;
                    },
                    sampleAppData.id,
                    sampleAppData.name
                );
        });

        it("should emit events for multiple app creations", async function () {
            const apps = [
                {...sampleAppData, id: "com.example.app1", name: "App 1"},
                {...sampleAppData, id: "com.example.app2", name: "App 2"}
            ];

            for (const appData of apps) {
                await expect(
                    plugin["createApp(string,string,string,uint16,uint16,uint16)"](
                        appData.id,
                        appData.name,
                        appData.description,
                        appData.protocolId,
                        appData.platformId,
                        appData.categoryId
                    )
                ).to.emit(plugin, "AppCreated")
                    .withArgs(
                        function (address: string) {
                            return address !== ethers.ZeroAddress;
                        },
                        appData.id,
                        appData.name
                    );
            }
        });
    });

    describe("edge cases and integration", function () {
        it("should handle apps with same name but different packages", async function () {
            const app1Data = {...sampleAppData, id: "com.company1.app"};
            const app2Data = {...sampleAppData, id: "com.company2.app"};

            const appManager1 = await devManager.createApp(app1Data, user1);
            const appManager2 = await devManager.createApp(app2Data, user1);

            const address1 = await plugin.getAppById(app1Data.id);
            const address2 = await plugin.getAppById(app2Data.id);

            expect(address1).to.not.equal(address2);
            expect(address1).to.equal(await appManager1.address());
            expect(address2).to.equal(await appManager2.address());
        });


        it("shouldn't handle very short strings", async function () {
            const longData = {
                id: "com.very.long.id.name.that.exceeds.normal.length.limits.and.keeps.going.on.and.on",
                name: "A",
                description: "A".repeat(2000),
                protocolId: 999,
                platformId: 999,
                categoryId: 999
            };

            await expect(
                plugin["createApp(string,string,string,uint16,uint16,uint16)"](
                    longData.id,
                    longData.name,
                    longData.description,
                    longData.protocolId,
                    longData.platformId,
                    longData.categoryId
                )
            ).to.be.revertedWithCustomError(await getFactory("AppAsset"), "AppError")
                .withArgs(2);
        });

        it("shouldn't handle very long strings", async function () {
            const longData = {
                id: "com.very.long.id.name.that.exceeds.normal.length.limits.and.keeps.going.on.and.on",
                name: "A".repeat(150),
                description: "A".repeat(2000),
                protocolId: 999,
                platformId: 999,
                categoryId: 999
            };

            await expect(
                plugin["createApp(string,string,string,uint16,uint16,uint16)"](
                    longData.id,
                    longData.name,
                    longData.description,
                    longData.protocolId,
                    longData.platformId,
                    longData.categoryId
                )
            ).to.be.revertedWithCustomError(await getFactory("AppAsset"), "AppError")
                .withArgs(2);
        });

        it("should create apps efficiently in bulk", async function () {
            const appCount = 5;

            for (let i = 0; i < appCount; i++) {
                const appData = {
                    id: `com.example.app${i}`,
                    name: `App ${i}`,
                    description: `Description for app ${i}`,
                    protocolId: (i % 3) + 1,
                    platformId: (i % 3) + 1,
                    categoryId: (i % 5) + 1
                };

                const appManager = await devManager.createApp(appData, user1);
                expect(await appManager.address()).to.not.equal(ethers.ZeroAddress);
            }

            for (let i = 0; i < appCount; i++) {
                const address = await plugin.getAppById(`com.example.app${i}`);
                expect(address).to.not.equal(ethers.ZeroAddress);
            }
        });

        it("should integrate with default configuration", async function () {
            const defaultAppData = Defaults.UserContractData.AppInfo;

            const appManager = await devManager.createApp(defaultAppData, user1);
            const general = await appManager.generalInfo()

            expect(general.id).to.equal(defaultAppData.id);
            expect(general.name).to.equal(defaultAppData.name);
            expect(general.description).to.equal(defaultAppData.description);
            expect(general.protocolId).to.equal(defaultAppData.protocolId);
            expect(general.platformId).to.equal(defaultAppData.platformId);
            expect(general.categoryId).to.equal(defaultAppData.categoryId);
        });
    });
}); 