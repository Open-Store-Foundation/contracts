import {expect} from "chai";
import {ethers} from "hardhat";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {AssetlinksOracle} from "../typechain-types";
import {expectSuccess, findEvent} from "./utils/contracts";
import {getBytes, id, parseEther} from "ethers";
import {ContractsDeployer} from "../scripts/deployer";
import {Defaults} from "../scripts/defaults";
import {AppManager, CoreManager, DevManager} from "../scripts/manager";
import {attachOrDeployMulticastContract} from "./utils/multicall";
import {disableLogging} from "./utils/logger";

describe("AssetlinksOracle", function () {
    let deployer: ContractsDeployer;
    let core: CoreManager;
    let devManager: DevManager;
    let appManager: AppManager;
    let oracle: AssetlinksOracle;
    let oracleUser: AssetlinksOracle;
    
    let admin: HardhatEthersSigner;
    let user: HardhatEthersSigner;

    const DOMAIN = "https://example.com";
    const FINGERPRINT = getBytes(id("test_fingerprint"));
    const CERT = getBytes(id("test_cert"));
    const PROOF = getBytes(id("test_proof"));

    beforeEach(async function () {
        disableLogging();

        [admin, user] = await ethers.getSigners();
        await attachOrDeployMulticastContract(admin);

        await admin.sendTransaction({to: user.address, value: parseEther("10")});

        deployer = new ContractsDeployer(
            admin, 
            Defaults.StoreConfig.LH,
            Defaults.GreenfieldContracts.BscTest, 
            Defaults.OracleFee.LH
        );

        await deployer.deployAndSetupAll();
        core = deployer.coreManager;
        oracle = core.contracts.oracle;
        oracleUser = oracle.connect(user);

        devManager = await core.devManager("TestDev", user);
        appManager = await devManager.createApp({
            id: "com.test.app",
            name: "Test App",
            description: "Test application for oracle tests",
            protocolId: 1,
            platformId: 1,
            categoryId: 1
        }, user);
    });

    describe("deployment", function () {
        it("should initialize with correct values", async function () {
            expect(await oracle.lastVerifiedRequestId()).to.equal(0);
            expect(await oracle.nextQueueRequestId()).to.equal(1);
            
            const [lastVerified, nextQueue, blockNumber] = await oracle.getContractState();
            expect(lastVerified).to.equal(0);
            expect(nextQueue).to.equal(1);
            expect(blockNumber).to.be.gt(0);
        });

        it("should set deployer as owner", async function () {
            expect(await oracle.owner()).to.equal(admin.address);
        });

        it("should have correct verification amount", async function () {
            expect(await oracle.getVerificationAmount()).to.equal(Defaults.OracleFee.LH);
        });
    });

    describe("enqueue function", function () {
        beforeEach(async function () {
            await appManager.updateAppOwner(DOMAIN, FINGERPRINT, CERT, PROOF);
        });

        it("should successfully enqueue verification request", async function () {
            const appAddress = await appManager.address();
            const tx = await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });
            const receipt = await tx.wait();
            expectSuccess(receipt);

            const event = findEvent("EnqueueVerification", receipt?.logs);
            expect(event).to.not.be.null;
            expect(event!.args[0]).to.equal(appAddress);
            expect(event!.args[1]).to.equal(1);
            expect(event!.args[2]).to.equal(1);

            expect(await oracle.nextQueueRequestId()).to.equal(2);

            const queuedRequest = await oracle.queue(1);
            expect(queuedRequest.target).to.equal(appAddress);
            expect(queuedRequest.version).to.equal(1);
        });

        it("should update app state correctly after enqueue", async function () {
            const appAddress = await appManager.address();
            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });

            const [status, version, pendingVersion] = await oracle.getLastAssetStatus(appAddress);
            expect(status).to.equal(0);
            expect(version).to.equal(0);
            expect(pendingVersion).to.equal(1);
        });

        it("should revert with ADDRESS_ZERO error for zero address", async function () {
            await expect(
                oracleUser["enqueue(address)"](ethers.ZeroAddress, {
                    value: Defaults.OracleFee.LH
                })
            ).to.be.revertedWithCustomError(oracle, "AssetlinksOracleError")
             .withArgs(1);
        });

        it("should revert with INSUFFICIENT_FEE error for low payment", async function () {
            const appAddress = await appManager.address();
            await expect(
                oracleUser["enqueue(address)"](appAddress, {
                    value: parseEther("0.001")
                })
            ).to.be.revertedWithCustomError(oracle, "AssetlinksOracleError")
             .withArgs(2);
        });

        it("should revert with INVALID_VERSION error for app with no owner version", async function () {
            const noOwnerAppManager = await devManager.createApp({
                id: "com.test.noowner",
                name: "No Owner App",
                description: "Test app for distribution plugin",
                protocolId: 1,
                platformId: 1,
                categoryId: 1
            }, user);

            const newAppAddress = await noOwnerAppManager.address();

            await expect(
                oracleUser["enqueue(address)"](newAppAddress, {
                    value: Defaults.OracleFee.LH
                })
            ).to.be.revertedWithCustomError(oracle, "AssetlinksOracleError")
             .withArgs(3);
        });

        it("should revert with ALREADY_IN_REVIEW error for duplicate request", async function () {
            const appAddress = await appManager.address();
            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });

            await expect(
                oracleUser["enqueue(address)"](appAddress, {
                    value: Defaults.OracleFee.LH
                })
            ).to.be.revertedWithCustomError(oracle, "AssetlinksOracleError")
             .withArgs(4);
        });

        it("should handle multiple apps enqueuing", async function () {
            const app2Manager = await devManager.createApp({
                id: "com.test.app2",
                name: "Test App 2",
                description: "Second test app",
                protocolId: 1,
                platformId: 1,
                categoryId: 1
            }, user);

            await app2Manager.updateAppOwner(DOMAIN + "2", FINGERPRINT, CERT, PROOF);

            const app1Address = await appManager.address();
            const app2Address = await app2Manager.address();

            await oracleUser["enqueue(address)"](app1Address, {
                value: Defaults.OracleFee.LH
            });

            await oracleUser["enqueue(address)"](app2Address, {
                value: Defaults.OracleFee.LH
            });

            expect(await oracle.nextQueueRequestId()).to.equal(3);

            const queuedRequest1 = await oracle.queue(1);
            const queuedRequest2 = await oracle.queue(2);

            expect(queuedRequest1.target).to.equal(app1Address);
            expect(queuedRequest2.target).to.equal(app2Address);
        });
    });

    describe("create app and enqueue multicall function", function () {
        it("should successfully enqueue through multicall", async function () {
            const devAppsPlugin = devManager.devPlugins.apps;
            const computedAddress = await devAppsPlugin.computeAppAddress(
                "com.test.app1", "Test App", "Test Desc", 1, 1, 1
            );

            const calldata = [];
            const createAppData = devAppsPlugin.interface.encodeFunctionData(
                "createApp(address,string,string,string,uint16,uint16,uint16)",
                [user.address, "com.test.app1", "Test App", "Test Desc", 1, 1, 1]
            );
            calldata.push({
                manager: await devManager.address(),
                plugin: await core.dev.apps.getAddress(),
                data: createAppData,
                value: 0
            });

            const appOwnerPlugin = deployer.appPlugins.owner.contract;
            const setOwnerData = appOwnerPlugin.interface.encodeFunctionData(
                "setAppOwner(address,string,bytes32[],bytes[],bytes[])",
                [user.address, DOMAIN, [FINGERPRINT], [CERT], [PROOF]]
            );
            calldata.push({
                manager: computedAddress,
                plugin: await appOwnerPlugin.getAddress(),
                data: setOwnerData,
                value: 0,
            });

            const data = oracle.interface.encodeFunctionData(
                "enqueue(address,address)",
                [user.address, computedAddress]
            );
            calldata.push({
                manager: await oracle.getAddress(),
                plugin: ethers.ZeroAddress,
                data: data,
                value: Defaults.OracleFee.LH
            });

            const multicall = core.contracts.multicall;
            const tx = await multicall.connect(user)
                .multicall(calldata, { value: Defaults.OracleFee.LH });

            const receipt = await tx.wait();
            expectSuccess(receipt);

            const event = findEvent("EnqueueVerification", receipt?.logs, oracle);
            expect(event).to.not.be.null;
            expect(event!.args[0]).to.equal(computedAddress);
            expect(event!.args[1]).to.equal(1);
            expect(event!.args[2]).to.equal(1);
        });

        it("should not revert with OwnableUnauthorizedAccount for unauthorized multicall", async function () {
            const appAddress = await appManager.address();
            await appManager.updateAppOwner(DOMAIN, FINGERPRINT, CERT, PROOF);

            const data = oracle.interface.encodeFunctionData(
                "enqueue(address,address)",
                [user.address, appAddress]
            );

            const multicall = core.contracts.multicall;
            const tx = await multicall.connect(user).multicall([{
                manager: await oracle.getAddress(),
                plugin: ethers.ZeroAddress,
                data: data,
                value: Defaults.OracleFee.LH
            }], { value: Defaults.OracleFee.LH });

            const receipt = await tx.wait();
            expectSuccess(receipt);

            const event = findEvent("EnqueueVerification", receipt?.logs, oracle);
            expect(event).to.not.be.null;
            expect(event!.args[0]).to.equal(appAddress);
        });
    });

    describe("finish function", function () {
        beforeEach(async function () {
            await appManager.updateAppOwner(DOMAIN, FINGERPRINT, CERT, PROOF);
            await oracleUser["enqueue(address)"](await appManager.address(), {
                value: Defaults.OracleFee.LH
            });
        });

        it("should successfully finish verification with success status", async function () {
            const appAddress = await appManager.address();
            const tx = await oracle.finish(1, 1);
            const receipt = await tx.wait();
            expectSuccess(receipt);

            const event = findEvent("FinalizeVerification", receipt?.logs);
            expect(event).to.not.be.null;
            expect(event!.args[0]).to.equal(appAddress);
            expect(event!.args[1]).to.equal(1);
            expect(event!.args[2]).to.equal(1);

            expect(await oracle.lastVerifiedRequestId()).to.equal(1);

            const [status, version, pendingVersion] = await oracle.getLastAssetStatus(appAddress);
            expect(status).to.equal(1);
            expect(version).to.equal(1);
            expect(pendingVersion).to.equal(0);
        });

        it("should successfully finish verification with failure status", async function () {
            const appAddress = await appManager.address();
            const tx = await oracle.finish(1, 2);
            const receipt = await tx.wait();
            expectSuccess(receipt);

            const event = findEvent("FinalizeVerification", receipt?.logs);
            expect(event).to.not.be.null;
            expect(event!.args[2]).to.equal(2);

            const [status, version, pendingVersion] = await oracle.getLastAssetStatus(appAddress);
            expect(status).to.equal(2);
            expect(version).to.equal(1);
            expect(pendingVersion).to.equal(0);
        });

        it("should clear queue entry after finishing", async function () {
            await oracle.finish(1, 1);

            const queuedRequest = await oracle.queue(1);
            expect(queuedRequest.target).to.equal(ethers.ZeroAddress);
            expect(queuedRequest.version).to.equal(0);
        });

        it("should revert with INVALID_REQUEST_ID for wrong request ID", async function () {
            await expect(
                oracle.finish(2, 1)
            ).to.be.revertedWithCustomError(oracle, "AssetlinksOracleError")
             .withArgs(5);
        });

        it("should revert with INVALID_REQUEST_ID for already processed request", async function () {
            await oracle.finish(1, 1);

            await expect(
                oracle.finish(1, 1)
            ).to.be.revertedWithCustomError(oracle, "AssetlinksOracleError")
             .withArgs(5);
        });

        it("should only allow owner to finish requests", async function () {
            await expect(
                oracleUser.finish(1, 1)
            ).to.be.revertedWithCustomError(oracle, "OwnableUnauthorizedAccount")
             .withArgs(user.address);
        });

        it("should process multiple requests in sequence", async function () {
            await oracle.finish(1, 1);

            const appOwnerPlugin = appManager["appPlugins"].owner;
            await appOwnerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](DOMAIN + "2", [FINGERPRINT], [CERT], [PROOF]);
            await oracleUser["enqueue(address)"](await appManager.address(), {
                value: Defaults.OracleFee.LH
            });

            await oracle.finish(2, 1);

            expect(await oracle.lastVerifiedRequestId()).to.equal(2);
        });
    });

    describe("getLastVerifiedAssetVersion function", function () {
        beforeEach(async function () {
            await appManager.updateAppOwner(DOMAIN, FINGERPRINT, CERT, PROOF);
        });

        it("should return 0 for unverified app", async function () {
            const verified = await oracle.getLastVerifiedAssetVersion(await appManager.address());
            expect(verified).to.equal(0);
        });

        it("should return version for successfully verified app", async function () {
            const appAddress = await appManager.address();
            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });
            await oracle.finish(1, 1);

            const verified = await oracle.getLastVerifiedAssetVersion(appAddress);
            expect(verified).to.equal(1);
        });

        it("should return 0 for failed verification", async function () {
            const appAddress = await appManager.address();
            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });
            await oracle.finish(1, 2);

            const verified = await oracle.getLastVerifiedAssetVersion(appAddress);
            expect(verified).to.equal(0);
        });

        it("should return 0 when app owner version changes after verification", async function () {
            const appAddress = await appManager.address();
            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });
            await oracle.finish(1, 1);

            const appOwnerPlugin = appManager["appPlugins"].owner;
            await appOwnerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](DOMAIN + "2", [FINGERPRINT], [CERT], [PROOF]);

            const verified = await oracle.getLastVerifiedAssetVersion(appAddress);
            expect(verified).to.equal(0);
        });

        it("should handle multiple verification cycles", async function () {
            const appAddress = await appManager.address();
            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });
            await oracle.finish(1, 1);

            let verified = await oracle.getLastVerifiedAssetVersion(appAddress);
            expect(verified).to.equal(1);

            const appOwnerPlugin = appManager["appPlugins"].owner;
            await appOwnerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](DOMAIN + "2", [FINGERPRINT], [CERT], [PROOF]);
            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });
            await oracle.finish(2, 1);

            verified = await oracle.getLastVerifiedAssetVersion(appAddress);
            expect(verified).to.equal(2);
        });
    });

    describe("view functions", function () {
        beforeEach(async function () {
            await appManager.updateAppOwner(DOMAIN, FINGERPRINT, CERT, PROOF);
        });

        it("should return correct oracle state", async function () {
            const [lastVerified, nextQueue, blockNumber] = await oracle.getContractState();
            expect(lastVerified).to.equal(0);
            expect(nextQueue).to.equal(1);
            expect(blockNumber).to.be.gt(0);

            await oracleUser["enqueue(address)"](await appManager.address(), {
                value: Defaults.OracleFee.LH
            });

            const [lastVerified2, nextQueue2] = await oracle.getContractState();
            expect(lastVerified2).to.equal(0);
            expect(nextQueue2).to.equal(2);
        });

        it("should return correct last state for app", async function () {
            const appAddress = await appManager.address();
            let [status, version, pendingVersion] = await oracle.getLastAssetStatus(appAddress);
            expect(status).to.equal(0);
            expect(version).to.equal(0);
            expect(pendingVersion).to.equal(0);

            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });

            [status, version, pendingVersion] = await oracle.getLastAssetStatus(appAddress);
            expect(status).to.equal(0);
            expect(version).to.equal(0);
            expect(pendingVersion).to.equal(1);

            await oracle.finish(1, 1);

            [status, version, pendingVersion] = await oracle.getLastAssetStatus(appAddress);
            expect(status).to.equal(1);
            expect(version).to.equal(1);
            expect(pendingVersion).to.equal(0);
        });

        it("should return correct last verified asset version", async function () {
            const appAddress = await appManager.address();

            expect(await oracle.getLastVerifiedAssetVersion(appAddress)).to.equal(0);

            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });
            await oracle.finish(1, 1);

            expect(await oracle.getLastVerifiedAssetVersion(appAddress)).to.equal(1);
        });
    });

    describe("edge cases and gas optimization", function () {
        beforeEach(async function () {
            await appManager.updateAppOwner(DOMAIN, FINGERPRINT, CERT, PROOF);
        });

        it("should handle exact verification fee amount", async function () {
            const tx = await oracleUser["enqueue(address)"](await appManager.address(), {
                value: Defaults.OracleFee.LH
            });
            const receipt = await tx.wait();
            expectSuccess(receipt);
        });

        it("should handle overpayment for verification fee", async function () {
            const tx = await oracleUser["enqueue(address)"](await appManager.address(), {
                value: parseEther("1.0")
            });
            const receipt = await tx.wait();
            expectSuccess(receipt);
        });

        it("should handle all verification status types", async function () {
            const statusTypes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

            for (let i = 0; i < statusTypes.length; i++) {
                const appOwnerPlugin = appManager["appPlugins"].owner;
                await appOwnerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](DOMAIN + i, [FINGERPRINT], [CERT], [PROOF]);
                await oracleUser["enqueue(address)"](await appManager.address(), {
                    value: Defaults.OracleFee.LH
                });

                const tx = await oracle.finish(i + 1, statusTypes[i]);
                const receipt = await tx.wait();
                expectSuccess(receipt);

                const event = findEvent("FinalizeVerification", receipt?.logs);
                expect(event!.args[2]).to.equal(statusTypes[i]);
            }
        });

        it("should handle large app addresses correctly", async function () {
            const largeAppManager = await devManager.createApp({
                id: "com.test.large",
                name: "Large App",
                description: "App with large address for testing",
                protocolId: 1,
                platformId: 1,
                categoryId: 1
            }, user);

            await largeAppManager.updateAppOwner(DOMAIN, FINGERPRINT, CERT, PROOF);

            const tx = await oracleUser["enqueue(address)"](await largeAppManager.address(), {
                value: Defaults.OracleFee.LH
            });
            const receipt = await tx.wait();
            expectSuccess(receipt);
        });
    });

    describe("integration with VersionableOwner", function () {
        it("should correctly read owner version from app", async function () {
            const appOwnerPlugin = appManager["appPlugins"].owner;
            expect(await appOwnerPlugin.ownerVersion()).to.equal(0);

            await appOwnerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](DOMAIN, [FINGERPRINT], [CERT], [PROOF]);
            expect(await appOwnerPlugin.ownerVersion()).to.equal(1);

            await oracleUser["enqueue(address)"](await appManager.address(), {
                value: Defaults.OracleFee.LH
            });

            const queuedRequest = await oracle.queue(1);
            expect(queuedRequest.version).to.equal(1);
        });

        it("should handle multiple owner version updates", async function () {
            const appOwnerPlugin = appManager["appPlugins"].owner;
            await appOwnerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](DOMAIN, [FINGERPRINT], [CERT], [PROOF]);
            await appOwnerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](DOMAIN + "2", [FINGERPRINT], [CERT], [PROOF]);
            await appOwnerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](DOMAIN + "3", [FINGERPRINT], [CERT], [PROOF]);

            expect(await appOwnerPlugin.ownerVersion()).to.equal(3);

            await oracleUser["enqueue(address)"](await appManager.address(), {
                value: Defaults.OracleFee.LH
            });

            const queuedRequest = await oracle.queue(1);
            expect(queuedRequest.version).to.equal(3);
        });

        it("should integrate with default configuration", async function () {
            const defaultAppManager = await devManager.createApp(Defaults.UserContractData.AppInfo, user);
            const defaultOwner = Defaults.UserContractData.owner;

            await defaultAppManager.updateAppOwner(
                defaultOwner.domain,
                defaultOwner.fingerprint,
                defaultOwner.cert,
                defaultOwner.proof
            );

            const appAddress = await defaultAppManager.address();
            await oracleUser["enqueue(address)"](appAddress, {
                value: Defaults.OracleFee.LH
            });
            await oracle.finish(1, 1);

            const verified = await oracle.getLastVerifiedAssetVersion(appAddress);
            expect(verified).to.equal(1);

            const generalInfo = await defaultAppManager.generalInfo();
            expect(generalInfo.id).to.equal(Defaults.UserContractData.AppInfo.id);
        });
    });
});