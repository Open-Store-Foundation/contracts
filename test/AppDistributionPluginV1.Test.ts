import {expect} from "chai";
import {ethers} from "hardhat";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {AppDistributionPluginV1} from "../typechain-types";
import {wait} from "./utils/contracts";
import {parseEther, toUtf8Bytes} from "ethers";
import {ContractsDeployer} from "../scripts/deployer";
import {Defaults} from "../scripts/defaults";
import {AppManager, CoreManager, DevManager} from "../scripts/manager";
import {attachOrDeployMulticastContract} from "./utils/multicall";
import {disableLogging} from "./utils/logger";

describe("AppDistributionPluginV1", function () {
    let deployer: ContractsDeployer;
    let core: CoreManager;
    let devManager: DevManager;
    let appManager: AppManager;
    let distributionPlugin: AppDistributionPluginV1;
    let admin: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;

    const sampleAppData = {
        id: "com.example.distribution",
        name: "Distribution Test App",
        description: "Test app for distribution plugin",
        protocolId: 1,
        platformId: 1,
        categoryId: 2
    };

    const sampleDistribution = {
        typeId: 1,
        sources: [
            toUtf8Bytes("https://github.com/example/app/releases/download/v1.0.0/app.apk"),
            toUtf8Bytes("https://cdn.example.com/apps/app-v1.0.0.apk")
        ]
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
        appManager = await devManager.createApp(sampleAppData, user1);
        distributionPlugin = appManager["appPlugins"].distribution;
    });

    describe("initial state", function () {
        it("should have empty distribution initially", async function () {
            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(0);
            expect(distribution.sources.length).to.equal(0);
        });

        it("should revert when getting source from empty distribution", async function () {
            await expect(
                distributionPlugin.getSource(0)
            ).to.be.reverted;
        });
    });

    describe("setDistribution (via AppManager)", function () {
        it("should set distribution successfully", async function () {
            const source = "https://gnfd-testnet-sp2.bnbchain.org/view/kittydev/open-store-external/org_openstore_example_android/v1.0.0/1.apk";
            
            await appManager.updateDistribution(source);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(1);
            expect(distribution.sources.length).to.equal(1);
        });

        it("should integrate with default distribution configuration", async function () {
            const defaultSource = Defaults.UserContractData.distribution.link;
            
            await appManager.updateDistribution(defaultSource);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(1);
            expect(distribution.sources.length).to.equal(1);
        });
    });

    describe("setDistribution (direct call)", function () {
        it("should set distribution successfully", async function () {
            const tx = await distributionPlugin["setDistribution(uint16,bytes[])"](
                sampleDistribution.typeId,
                sampleDistribution.sources
            );
            const receipt = await wait(Promise.resolve(tx));
            
            expect(receipt.status).to.equal(1);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(sampleDistribution.typeId);
            expect(distribution.sources.length).to.equal(sampleDistribution.sources.length);
            expect(distribution.sources[0]).to.equal(ethers.hexlify(sampleDistribution.sources[0]));
            expect(distribution.sources[1]).to.equal(ethers.hexlify(sampleDistribution.sources[1]));
        });

        it("should update existing distribution", async function () {
            await distributionPlugin["setDistribution(uint16,bytes[])"](
                sampleDistribution.typeId,
                sampleDistribution.sources
            );

            const newDistribution = {
                typeId: 2,
                sources: [toUtf8Bytes("https://newcdn.example.com/app-v2.0.0.apk")]
            };

            await distributionPlugin["setDistribution(uint16,bytes[])"](
                newDistribution.typeId,
                newDistribution.sources
            );

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(newDistribution.typeId);
            expect(distribution.sources.length).to.equal(1);
            expect(distribution.sources[0]).to.equal(ethers.hexlify(newDistribution.sources[0]));
        });

        it("should handle empty sources array", async function () {
            await distributionPlugin["setDistribution(uint16,bytes[])"](5, []);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(5);
            expect(distribution.sources.length).to.equal(0);
        });

        it("should handle multiple sources", async function () {
            const multipleSources = [
                toUtf8Bytes("https://source1.example.com/app.apk"),
                toUtf8Bytes("https://source2.example.com/app.apk"),
                toUtf8Bytes("https://source3.example.com/app.apk"),
                toUtf8Bytes("ipfs://QmExampleHash")
            ];

            await distributionPlugin["setDistribution(uint16,bytes[])"](3, multipleSources);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(3);
            expect(distribution.sources.length).to.equal(4);
            
            for (let i = 0; i < multipleSources.length; i++) {
                expect(distribution.sources[i]).to.equal(ethers.hexlify(multipleSources[i]));
            }
        });

        it("should revert when called by non-owner", async function () {
            const devManager2 = await core.devManager("TestDev2", user2);
            const appManager2 = await devManager2.createApp(sampleAppData, user2);
            const distributionPlugin2 = appManager2["appPlugins"].distribution.connect(user1);

            await expect(
                distributionPlugin2["setDistribution(uint16,bytes[])"](
                    sampleDistribution.typeId,
                    sampleDistribution.sources
                )
            ).to.be.revertedWithCustomError(distributionPlugin2, "OwnableDelegateUnauthorizedAccount")
            .withArgs(user1.address);
        });
    });

    describe("getSource", function () {
        beforeEach(async function () {
            await distributionPlugin["setDistribution(uint16,bytes[])"](
                sampleDistribution.typeId,
                sampleDistribution.sources
            );
        });

        it("should return correct source by index", async function () {
            const source0 = await distributionPlugin.getSource(0);
            const source1 = await distributionPlugin.getSource(1);

            expect(source0).to.equal(ethers.hexlify(sampleDistribution.sources[0]));
            expect(source1).to.equal(ethers.hexlify(sampleDistribution.sources[1]));
        });

        it("should revert when index is out of bounds", async function () {
            await expect(
                distributionPlugin.getSource(2)
            ).to.be.reverted;

            await expect(
                distributionPlugin.getSource(999)
            ).to.be.reverted;
        });

        it("should handle single source", async function () {
            const singleSource = [toUtf8Bytes("https://single.example.com/app.apk")];
            
            await distributionPlugin["setDistribution(uint16,bytes[])"](1, singleSource);

            const source = await distributionPlugin.getSource(0);
            expect(source).to.equal(ethers.hexlify(singleSource[0]));

            await expect(
                distributionPlugin.getSource(1)
            ).to.be.reverted;
        });
    });

    describe("getDistribution", function () {
        it("should return complete distribution data", async function () {
            await distributionPlugin["setDistribution(uint16,bytes[])"](
                sampleDistribution.typeId,
                sampleDistribution.sources
            );

            const distribution = await distributionPlugin.getDistribution();
            
            expect(distribution.typeId).to.equal(sampleDistribution.typeId);
            expect(distribution.sources.length).to.equal(sampleDistribution.sources.length);
            
            for (let i = 0; i < sampleDistribution.sources.length; i++) {
                expect(distribution.sources[i]).to.equal(ethers.hexlify(sampleDistribution.sources[i]));
            }
        });

        it("should return updated distribution after changes", async function () {
            await distributionPlugin["setDistribution(uint16,bytes[])"](1, [toUtf8Bytes("old")]);
            
            let distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(1);
            expect(distribution.sources.length).to.equal(1);

            const newSources = [
                toUtf8Bytes("new1"),
                toUtf8Bytes("new2")
            ];
            await distributionPlugin["setDistribution(uint16,bytes[])"](2, newSources);

            distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(2);
            expect(distribution.sources.length).to.equal(2);
            expect(distribution.sources[0]).to.equal(ethers.hexlify(newSources[0]));
            expect(distribution.sources[1]).to.equal(ethers.hexlify(newSources[1]));
        });
    });

    describe("edge cases", function () {
        it("should handle unicode and special characters in sources", async function () {
            const unicodeSources = [
                toUtf8Bytes("https://例え.com/アプリ.apk"),
                toUtf8Bytes("https://example.com/app-🚀.apk"),
                toUtf8Bytes("magnet:?xt=urn:btih:example&dn=app.apk")
            ];

            await distributionPlugin["setDistribution(uint16,bytes[])"](99, unicodeSources);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(99);
            expect(distribution.sources.length).to.equal(3);
            
            for (let i = 0; i < unicodeSources.length; i++) {
                expect(distribution.sources[i]).to.equal(ethers.hexlify(unicodeSources[i]));
                
                const source = await distributionPlugin.getSource(i);
                expect(source).to.equal(ethers.hexlify(unicodeSources[i]));
            }
        });

        it("should handle maximum typeId value", async function () {
            const maxTypeId = 65535;
            const sources = [toUtf8Bytes("https://max.example.com/app.apk")];

            await distributionPlugin["setDistribution(uint16,bytes[])"](maxTypeId, sources);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(maxTypeId);
        });

        it("should handle empty bytes in sources", async function () {
            const emptySources = [
                toUtf8Bytes(""),
                toUtf8Bytes("https://valid.example.com/app.apk"),
                toUtf8Bytes("")
            ];

            await distributionPlugin["setDistribution(uint16,bytes[])"](1, emptySources);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.sources.length).to.equal(3);
            expect(distribution.sources[0]).to.equal("0x");
            expect(distribution.sources[2]).to.equal("0x");
        });
    });

    describe("integration with default configuration", function () {
        it("should integrate with complete app lifecycle", async function () {
            const defaultAppData = Defaults.UserContractData.AppInfo;
            const defaultDistributionLink = Defaults.UserContractData.distribution.link;
            
            const defaultAppManager = await devManager.createApp(defaultAppData, user1);
            const defaultDistributionPlugin = defaultAppManager["appPlugins"].distribution;

            await defaultAppManager.updateDistribution(defaultDistributionLink);

            const distribution = await defaultDistributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(1);
            expect(distribution.sources.length).to.equal(1);

            const generalInfo = await defaultAppManager.generalInfo();
            expect(generalInfo.id).to.equal(defaultAppData.id);
            expect(generalInfo.name).to.equal(defaultAppData.name);
        });

        it("should work with app builds and distribution together", async function () {
            await appManager.addBuild(1);
            await appManager.updateDistribution("https://example.com/app-v1.0.0.apk");

            const buildsPlugin = appManager["appPlugins"].builds;
            const lastVersionCode = await buildsPlugin.getLastVersionCode();
            expect(lastVersionCode).to.equal(1);

            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(1);
            expect(distribution.sources.length).to.equal(1);

            const generalInfo = await appManager.generalInfo();
            expect(generalInfo.id).to.equal(sampleAppData.id);
        });
    });
}); 