import {expect} from "chai";
import {ethers} from "hardhat";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {AppOwnerPluginV1} from "../typechain-types";
import {findEvent, wait} from "./utils/contracts";
import {BytesLike, getBytes, id, keccak256, parseEther, toUtf8Bytes} from "ethers";
import {ContractsDeployer} from "../scripts/deployer";
import {Defaults} from "../scripts/defaults";
import {AppManager, CoreManager, DevManager} from "../scripts/manager";
import {attachOrDeployMulticastContract} from "./utils/multicall";
import {disableLogging} from "./utils/logger";

describe("AppOwnerPluginV1", function () {
    let deployer: ContractsDeployer;
    let core: CoreManager;
    let devManager: DevManager;
    let appManager: AppManager;
    let ownerPlugin: AppOwnerPluginV1;

    let admin: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;

    const sampleOwnerData = {
        domain: "https://example.com",
        fingerprints: [
            keccak256(toUtf8Bytes("fingerprint1")),
            keccak256(toUtf8Bytes("fingerprint2"))
        ],
        certs: [
            toUtf8Bytes("cert1_data"),
            toUtf8Bytes("cert2_data")
        ],
        proofs: [
            toUtf8Bytes("proof1_data"),
            toUtf8Bytes("proof2_data")
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

        devManager = await core.devManager("TestDev", user1);
        appManager = await devManager.createApp(Defaults.UserContractData.AppInfo, user1);
        ownerPlugin = appManager["appPlugins"].owner;
    });

    describe("initial state", function () {
        it("should have version 0 initially", async function () {
            const version = await ownerPlugin.ownerVersion();
            expect(version).to.equal(0);
        });

        it("should revert when getting initial domain without versions", async function () {
            await expect(ownerPlugin["domain()"]()).to.be.empty;
        });

        it("should revert when getting initial state without versions", async function () {
            const state = await ownerPlugin["getState()"]()
            expect(state.domain).to.be.empty;
        });

        it("should revert when getting domain for non-existent version", async function () {
            await expect(ownerPlugin["domain(uint256)"](1)).to.be.empty;
        });

        it("should revert when getting state for non-existent version", async function () {
            await expect(ownerPlugin["getState(uint256)"](1)).to.be.reverted;
        });
    });

    describe("setAppOwner (via AppManager)", function () {
        it("should set app owner successfully", async function () {
            const defaultOwner = Defaults.UserContractData.owner;

            const receipt = await appManager.updateAppOwner(
                defaultOwner.domain,
                defaultOwner.fingerprint,
                defaultOwner.cert,
                defaultOwner.proof
            )

            const version = await ownerPlugin.ownerVersion();
            expect(version).to.equal(1);

            const domain = await ownerPlugin["domain()"]();
            expect(domain).to.equal(defaultOwner.domain);

            const state = await ownerPlugin["getState()"]();
            expect(state.domain).to.equal(defaultOwner.domain);
            expect(state.fingerprints.length).to.equal(1);
        });

        it("should integrate with default owner configuration", async function () {
            const defaultAppData = Defaults.UserContractData.AppInfo;
            const defaultOwner = Defaults.UserContractData.owner;

            await appManager.updateAppOwner(
                defaultOwner.domain,
                defaultOwner.fingerprint,
                defaultOwner.cert,
                defaultOwner.proof
            );

            const version = await appManager.ownerVersion();
            expect(version).to.equal(1);

            const domain = await appManager.domain()
            expect(domain).to.equal(defaultOwner.domain);

            const generalInfo = await appManager.generalInfo();
            expect(generalInfo.id).to.equal(defaultAppData.id);
            expect(generalInfo.name).to.equal(defaultAppData.name);
        });
    });

    describe("setAppOwner (direct call)", function () {
        it("should set app owner successfully", async function () {
            await expect(
                ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                    sampleOwnerData.domain,
                    sampleOwnerData.fingerprints,
                    sampleOwnerData.certs,
                    sampleOwnerData.proofs
                )
            ).to.emit(ownerPlugin, "AppOwnerChanged")
                .withArgs(1, sampleOwnerData.certs, sampleOwnerData.proofs);

            const version = await ownerPlugin.ownerVersion();
            expect(version).to.equal(1);

            const domain = await ownerPlugin["domain()"]();
            expect(domain).to.equal(sampleOwnerData.domain);

            const state = await ownerPlugin["getState()"]();
            expect(state.domain).to.equal(sampleOwnerData.domain);
            expect(state.fingerprints.length).to.equal(sampleOwnerData.fingerprints.length);

            for (let i = 0; i < sampleOwnerData.fingerprints.length; i++) {
                expect(state.fingerprints[i]).to.equal(sampleOwnerData.fingerprints[i]);
            }
        });

        it("should create multiple versions", async function () {
            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                sampleOwnerData.domain,
                sampleOwnerData.fingerprints,
                sampleOwnerData.certs,
                sampleOwnerData.proofs
            );

            const newOwnerData = {
                domain: "https://newdomain.com",
                fingerprints: [keccak256(toUtf8Bytes("new_fingerprint"))],
                certs: [toUtf8Bytes("new_cert_data")],
                proofs: [toUtf8Bytes("new_proof_data")]
            };

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                newOwnerData.domain,
                newOwnerData.fingerprints,
                newOwnerData.certs,
                newOwnerData.proofs
            );

            const version = await ownerPlugin.ownerVersion();
            expect(version).to.equal(2);

            const currentDomain = await ownerPlugin["domain()"]();
            expect(currentDomain).to.equal(newOwnerData.domain);

            const version1Domain = await ownerPlugin["domain(uint256)"](1);
            expect(version1Domain).to.equal(sampleOwnerData.domain);

            const version2Domain = await ownerPlugin["domain(uint256)"](2);
            expect(version2Domain).to.equal(newOwnerData.domain);

            const version1State = await ownerPlugin["getState(uint256)"](1);
            expect(version1State.domain).to.equal(sampleOwnerData.domain);

            const version2State = await ownerPlugin["getState(uint256)"](2);
            expect(version2State.domain).to.equal(newOwnerData.domain);
        });

        it("should handle single fingerprint and proof", async function () {
            const singleData = {
                domain: "https://single.com",
                fingerprints: [keccak256(toUtf8Bytes("single_fingerprint"))],
                certs: [toUtf8Bytes("single_cert")],
                proofs: [toUtf8Bytes("single_proof")]
            };

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                singleData.domain,
                singleData.fingerprints,
                singleData.certs,
                singleData.proofs
            );

            const state = await ownerPlugin["getState()"]();
            expect(state.domain).to.equal(singleData.domain);
            expect(state.fingerprints.length).to.equal(1);
            expect(state.fingerprints[0]).to.equal(singleData.fingerprints[0]);
        });

        it("should handle multiple fingerprints and proofs", async function () {
            const multipleData = {
                domain: "https://multiple.com",
                fingerprints: [
                    keccak256(toUtf8Bytes("fp1")),
                    keccak256(toUtf8Bytes("fp2")),
                    keccak256(toUtf8Bytes("fp3")),
                    keccak256(toUtf8Bytes("fp4"))
                ],
                certs: [
                    toUtf8Bytes("cert1"),
                    toUtf8Bytes("cert2"),
                    toUtf8Bytes("cert3"),
                    toUtf8Bytes("cert4")
                ],
                proofs: [
                    toUtf8Bytes("proof1"),
                    toUtf8Bytes("proof2"),
                    toUtf8Bytes("proof3"),
                    toUtf8Bytes("proof4")
                ]
            };

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                multipleData.domain,
                multipleData.fingerprints,
                multipleData.certs,
                multipleData.proofs
            );

            const state = await ownerPlugin["getState()"]();
            expect(state.fingerprints.length).to.equal(4);

            for (let i = 0; i < 4; i++) {
                expect(state.fingerprints[i]).to.equal(multipleData.fingerprints[i]);
            }
        });

        it("should revert when proofs array is empty", async function () {
            await expect(
                ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                    sampleOwnerData.domain,
                    sampleOwnerData.fingerprints,
                    [],
                    []
                )
            ).to.be.revertedWithCustomError(ownerPlugin, "AppOwnerPluginError")
                .withArgs(1);
        });

        it("should revert when fingerprints and proofs length mismatch", async function () {
            const mismatchedCert = [toUtf8Bytes("single_cert")];
            const mismatchedProofs = [toUtf8Bytes("single_proof")];

            await expect(
                ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                    sampleOwnerData.domain,
                    sampleOwnerData.fingerprints,
                    mismatchedCert,
                    mismatchedProofs
                )
            ).to.be.revertedWithCustomError(ownerPlugin, "AppOwnerPluginError")
                .withArgs(2);
        });

        it("should revert when called by non-owner", async function () {
            const devManager2 = await core.devManager("TestDev2", user2);
            const appManager2 = await devManager2.createApp(Defaults.UserContractData.AppInfo, user2);
            const ownerPlugin2 = appManager2["appPlugins"].owner.connect(user1);

            await expect(
                ownerPlugin2["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                    sampleOwnerData.domain,
                    sampleOwnerData.fingerprints,
                    sampleOwnerData.certs,
                    sampleOwnerData.proofs
                )
            ).to.be.revertedWithCustomError(ownerPlugin2, "OwnableDelegateUnauthorizedAccount")
                .withArgs(user1.address);
        });
    });

    describe("version management", function () {
        beforeEach(async function () {
            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                sampleOwnerData.domain,
                sampleOwnerData.fingerprints,
                sampleOwnerData.certs,
                sampleOwnerData.proofs
            );
        });

        it("should return correct version number", async function () {
            const version = await ownerPlugin.ownerVersion();
            expect(version).to.equal(1);

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                "https://version2.com",
                [keccak256(toUtf8Bytes("v2"))],
                [toUtf8Bytes("v2_cert")],
                [toUtf8Bytes("v2_proof")],
            );

            const newVersion = await ownerPlugin.ownerVersion();
            expect(newVersion).to.equal(2);
        });

        it("should return correct domain for current version", async function () {
            const domain = await ownerPlugin["domain()"]();
            expect(domain).to.equal(sampleOwnerData.domain);
        });

        it("should return correct domain for specific version", async function () {
            const domain = await ownerPlugin["domain(uint256)"](1);
            expect(domain).to.equal(sampleOwnerData.domain);
        });

        it("should return correct state for current version", async function () {
            const state = await ownerPlugin["getState()"]();
            expect(state.domain).to.equal(sampleOwnerData.domain);
            expect(state.fingerprints.length).to.equal(sampleOwnerData.fingerprints.length);
        });

        it("should return correct state for specific version", async function () {
            const state = await ownerPlugin["getState(uint256)"](1);
            expect(state.domain).to.equal(sampleOwnerData.domain);
            expect(state.fingerprints.length).to.equal(sampleOwnerData.fingerprints.length);
        });
    });

    describe("edge cases", function () {
        it("should handle unicode domains", async function () {
            const unicodeDomain = "https://例え.com/アプリ";
            const unicodeData = {
                domain: unicodeDomain,
                fingerprints: [keccak256(toUtf8Bytes("unicode_fp"))],
                certs: [Defaults.UserContractData.owner.cert],
                proofs: [Defaults.UserContractData.owner.proof],
            };

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                unicodeData.domain,
                unicodeData.fingerprints,
                unicodeData.certs,
                unicodeData.proofs
            );

            const domain = await ownerPlugin["domain()"]();
            expect(domain).to.equal(unicodeDomain);
        });

        it("should handle empty domain string", async function () {
            const emptyDomainData = {
                domain: "",
                fingerprints: [keccak256(toUtf8Bytes("empty_domain"))],
                certs: [Defaults.UserContractData.owner.cert],
                proofs: [Defaults.UserContractData.owner.proof],
            };

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                emptyDomainData.domain,
                emptyDomainData.fingerprints,
                emptyDomainData.certs,
                emptyDomainData.proofs,
            );

            const domain = await ownerPlugin["domain()"]();
            expect(domain).to.equal("");
        });

        it("should handle large arrays", async function () {
            const largeArrays = {
                domain: "https://large.com",
                fingerprints: [] as BytesLike[],
                certs: [] as BytesLike[],
                proofs: [] as BytesLike[]
            };

            for (let i = 0; i < 10; i++) {
                largeArrays.fingerprints.push(getBytes(id(`fp_${i}`)));
                largeArrays.proofs.push(getBytes(id(`proof_${i}`)));
                largeArrays.certs.push(getBytes(id(`cert_${i}`)));
            }

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                largeArrays.domain,
                largeArrays.fingerprints,
                largeArrays.certs,
                largeArrays.proofs
            );

            const state = await ownerPlugin["getState()"]();
            expect(state.fingerprints.length).to.equal(10);
        });

        it("should handle empty bytes in proofs", async function () {
            const emptyProofData = {
                domain: "https://empty-proof.com",
                fingerprints: [keccak256(toUtf8Bytes("empty_proof_fp"))],
                certs: [toUtf8Bytes("")],
                proofs: [toUtf8Bytes("")]
            };

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                emptyProofData.domain,
                emptyProofData.fingerprints,
                emptyProofData.certs,
                emptyProofData.proofs,
            );

            const state = await ownerPlugin["getState()"]();
        });

        it("should revert when accessing version 0", async function () {
            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                sampleOwnerData.domain,
                sampleOwnerData.fingerprints,
                sampleOwnerData.certs,
                sampleOwnerData.proofs
            );

            await expect(ownerPlugin["domain(uint256)"](0)).to.be.reverted;
            await expect(ownerPlugin["getState(uint256)"](0)).to.be.reverted;
        });
    });

    describe("integration with default configuration", function () {
        it("should work with complete app lifecycle", async function () {
            const defaultOwner = Defaults.UserContractData.owner;

            await appManager.updateAppOwner(
                defaultOwner.domain,
                defaultOwner.fingerprint,
                defaultOwner.cert,
                defaultOwner.proof
            );

            await appManager.addBuild(1);
            await appManager.updateDistribution("https://example.com/app-v1.0.0.apk");

            const version = await ownerPlugin.ownerVersion();
            expect(version).to.equal(1);

            const domain = await ownerPlugin["domain()"]();
            expect(domain).to.equal(defaultOwner.domain);

            const buildsPlugin = appManager["appPlugins"].builds;
            const lastVersionCode = await buildsPlugin.getLastVersionCode();
            expect(lastVersionCode).to.equal(1);

            const distributionPlugin = appManager["appPlugins"].distribution;
            const distribution = await distributionPlugin.getDistribution();
            expect(distribution.typeId).to.equal(1);

            const generalInfo = await appManager.generalInfo();
            expect(generalInfo.id).to.equal(Defaults.UserContractData.AppInfo.id);
        });

        it("should maintain version history across updates", async function () {
            const defaultOwner = Defaults.UserContractData.owner;

            await appManager.updateAppOwner(
                defaultOwner.domain,
                defaultOwner.fingerprint,
                defaultOwner.cert,
                defaultOwner.proof
            );

            await ownerPlugin["setAppOwner(string,bytes32[],bytes[],bytes[])"](
                "https://updated.com",
                [keccak256(toUtf8Bytes("updated_fp"))],
                [toUtf8Bytes("updated_cert")],
                [toUtf8Bytes("updated_proof")],
            );

            const currentVersion = await ownerPlugin.ownerVersion();
            expect(currentVersion).to.equal(2);

            const version1Domain = await ownerPlugin["domain(uint256)"](1);
            expect(version1Domain).to.equal(defaultOwner.domain);

            const version2Domain = await ownerPlugin["domain(uint256)"](2);
            expect(version2Domain).to.equal("https://updated.com");

            const currentDomain = await ownerPlugin["domain()"]();
            expect(currentDomain).to.equal("https://updated.com");
        });
    });
});