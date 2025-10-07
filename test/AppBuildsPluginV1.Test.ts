import {expect} from "chai";
import {ethers} from "hardhat";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {wait} from "./utils/contracts";
import {AppBuildsPluginV1} from "../typechain-types";
import {parseEther, sha256} from "ethers";
import {ContractsDeployer} from "../scripts/deployer";
import {Defaults} from "../scripts/defaults";
import {AppManager, CoreManager, DevManager} from "../scripts/manager";
import {attachOrDeployMulticastContract} from "./utils/multicall";
import {disableLogging} from "./utils/logger";

describe("AppBuildsPluginV1", function () {
    let deployer: ContractsDeployer;
    let core: CoreManager;
    let devManager: DevManager;
    let appManager: AppManager;
    let buildsPlugin: AppBuildsPluginV1;
    let admin: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;

    const sampleAppData = {
        id: "com.example.testapp",
        name: "Test App",
        description: "A test application for builds",
        protocolId: 1,
        platformId: 1,
        categoryId: 2
    };

    const sampleBuild = {
        referenceId: "0x1234567890123456789012345678901234567890123456789012345678901234",
        protocolId: 1,
        versionName: "1.0.0",
        versionCode: 1,
        checksum: sha256("0x")
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
        buildsPlugin = appManager["appPlugins"].builds;
    });

    describe("initial state", function () {
        it("should have zero last version code initially", async function () {
            const lastVersionCode = await buildsPlugin.getLastVersionCode();
            expect(lastVersionCode).to.equal(0);
        });

        it("should return false for non-existent builds", async function () {
            const hasBuild = await buildsPlugin.hasBuild(1);
            expect(hasBuild).to.be.false;
        });

        it("should return empty build for non-existent version", async function () {
            const build = await buildsPlugin.getBuild(1);
            expect(build.versionCode).to.equal(0);
            expect(build.versionName).to.equal("");
            expect(build.referenceId).to.equal("0x");
            expect(build.protocolId).to.equal(0);
        });
    });

    describe("addBuild (via AppManager)", function () {
        it("should add build successfully", async function () {
            await appManager.addBuild(sampleBuild.versionCode);

            const lastVersionCode = await buildsPlugin.getLastVersionCode();
            expect(lastVersionCode).to.equal(sampleBuild.versionCode);

            const hasBuild = await buildsPlugin.hasBuild(sampleBuild.versionCode);
            expect(hasBuild).to.be.true;

            const build = await buildsPlugin.getBuild(sampleBuild.versionCode);
            expect(build.versionCode).to.equal(sampleBuild.versionCode);
            expect(build.versionName).to.equal("1.0.0");
            expect(build.protocolId).to.equal(1);
        });

        it("should add multiple builds with increasing version codes", async function () {
            const versionCodes = [1, 2, 3];

            for (const versionCode of versionCodes) {
                await appManager.addBuild(versionCode);
                
                const lastVersionCode = await buildsPlugin.getLastVersionCode();
                expect(lastVersionCode).to.equal(versionCode);
                
                const hasBuild = await buildsPlugin.hasBuild(versionCode);
                expect(hasBuild).to.be.true;
            }

            const finalLastVersionCode = await buildsPlugin.getLastVersionCode();
            expect(finalLastVersionCode).to.equal(3);
        });
    });

    describe("addBuild (direct call)", function () {
        it("should add build successfully", async function () {
            const tx = await buildsPlugin["addBuild((bytes,uint16,string,uint256,bytes32))"](sampleBuild);
            const receipt = await wait(Promise.resolve(tx));
            
            expect(receipt.status).to.equal(1);

            const lastVersionCode = await buildsPlugin.getLastVersionCode();
            expect(lastVersionCode).to.equal(sampleBuild.versionCode);

            const hasBuild = await buildsPlugin.hasBuild(sampleBuild.versionCode);
            expect(hasBuild).to.be.true;

            const build = await buildsPlugin.getBuild(sampleBuild.versionCode);
            expect(build.referenceId).to.equal(sampleBuild.referenceId);
            expect(build.protocolId).to.equal(sampleBuild.protocolId);
            expect(build.versionName).to.equal(sampleBuild.versionName);
            expect(build.versionCode).to.equal(sampleBuild.versionCode);
        });

        it("should add multiple builds with increasing version codes", async function () {
            const builds = [
                { ...sampleBuild, versionCode: 1, versionName: "1.0.0" },
                { ...sampleBuild, versionCode: 2, versionName: "1.1.0" },
                { ...sampleBuild, versionCode: 3, versionName: "1.2.0" }
            ];

            for (const build of builds) {
                await buildsPlugin["addBuild((bytes,uint16,string,uint256,bytes32))"](build);
                
                const lastVersionCode = await buildsPlugin.getLastVersionCode();
                expect(lastVersionCode).to.equal(build.versionCode);
                
                const hasBuild = await buildsPlugin.hasBuild(build.versionCode);
                expect(hasBuild).to.be.true;
            }

            const finalLastVersionCode = await buildsPlugin.getLastVersionCode();
            expect(finalLastVersionCode).to.equal(3);
        });

        it("should revert when version code is zero", async function () {
            const invalidBuild = { ...sampleBuild, versionCode: 0 };

            await expect(
                buildsPlugin["addBuild((bytes,uint16,string,uint256,bytes32))"](invalidBuild)
            ).to.be.revertedWithCustomError(buildsPlugin, "AppBuildsPluginError")
            .withArgs(1);
        });

        it("should revert when version code is not higher than last", async function () {
            await buildsPlugin["addBuild((bytes,uint16,string,uint256,bytes32))"](sampleBuild);

            const duplicateBuild = { ...sampleBuild, versionName: "1.0.1" };

            await expect(
                buildsPlugin["addBuild((bytes,uint16,string,uint256,bytes32))"](duplicateBuild)
            ).to.be.revertedWithCustomError(buildsPlugin, "AppBuildsPluginError")
            .withArgs(2);
        });

        it("should revert when called by non-owner", async function () {
            const devManager2 = await core.devManager("TestDev2", user2);
            const appManager2 = await devManager2.createApp(sampleAppData, user2);
            const buildsPlugin2 = appManager2["appPlugins"].builds.connect(user1);

            await expect(
                buildsPlugin2["addBuild((bytes,uint16,string,uint256,bytes32))"](sampleBuild)
            ).to.be.revertedWithCustomError(buildsPlugin2, "OwnableDelegateUnauthorizedAccount")
            .withArgs(user1.address);
        });
    });

    describe("getBuild and hasBuild", function () {
        it("should return correct build data", async function () {
            await buildsPlugin["addBuild((bytes,uint16,string,uint256,bytes32))"](sampleBuild);

            const build = await buildsPlugin.getBuild(sampleBuild.versionCode);
            expect(build.referenceId).to.equal(sampleBuild.referenceId);
            expect(build.protocolId).to.equal(sampleBuild.protocolId);
            expect(build.versionName).to.equal(sampleBuild.versionName);
            expect(build.versionCode).to.equal(sampleBuild.versionCode);

            const hasBuild = await buildsPlugin.hasBuild(sampleBuild.versionCode);
            expect(hasBuild).to.be.true;
        });

        it("should return false for non-existing builds", async function () {
            const hasBuild = await buildsPlugin.hasBuild(999);
            expect(hasBuild).to.be.false;
        });

        it("should handle edge cases", async function () {
            const unicodeBuild = {
                ...sampleBuild,
                versionCode: 2,
                versionName: "版本 1.0.0 🚀"
            };

            await buildsPlugin["addBuild((bytes,uint16,string,uint256,bytes32))"](sampleBuild);
            await buildsPlugin["addBuild((bytes,uint16,string,uint256,bytes32))"](unicodeBuild);

            const build1 = await buildsPlugin.getBuild(1);
            const build2 = await buildsPlugin.getBuild(2);

            expect(build1.versionName).to.equal("1.0.0");
            expect(build2.versionName).to.equal("版本 1.0.0 🚀");
        });
    });

    describe("integration with default configuration", function () {
        it("should integrate with default app configuration", async function () {
            const defaultAppData = Defaults.UserContractData.AppInfo;
            const defaultAppManager = await devManager.createApp(defaultAppData, user1);
            const defaultBuildsPlugin = defaultAppManager["appPlugins"].builds;

            await defaultAppManager.addBuild(1);

            const lastVersionCode = await defaultBuildsPlugin.getLastVersionCode();
            expect(lastVersionCode).to.equal(1);

            const hasBuild = await defaultBuildsPlugin.hasBuild(1);
            expect(hasBuild).to.be.true;

            const build = await defaultBuildsPlugin.getBuild(1);
            expect(build.versionCode).to.equal(1);
            expect(build.versionName).to.equal("1.0.0");
            expect(build.protocolId).to.equal(1);
        });

        it("should work with the complete app lifecycle", async function () {
            await appManager.addBuild(1);
            await appManager.addBuild(2);
            await appManager.addBuild(3);

            const generalInfo = await appManager.generalInfo();
            expect(generalInfo.id).to.equal(sampleAppData.id);
            expect(generalInfo.name).to.equal(sampleAppData.name);

            const lastVersionCode = await buildsPlugin.getLastVersionCode();
            expect(lastVersionCode).to.equal(3);

            for (let i = 1; i <= 3; i++) {
                const hasBuild = await buildsPlugin.hasBuild(i);
                expect(hasBuild).to.be.true;
            }
        });
    });
}); 