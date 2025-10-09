import {expect} from "chai";
import {ethers} from "hardhat";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {getFactory, wait} from "./utils/contracts";
import {id, parseEther} from "ethers";
import {ContractsDeployer} from "../scripts/deployer";
import {Defaults} from "../scripts/defaults";
import {CoreManager} from "../scripts/manager";
import {attachOrDeployMulticastContract} from "./utils/multicall";
import {disableLogging} from "./utils/logger";

describe("PublisherAccountFactory", function () {
    let deployer: ContractsDeployer;
    let core: CoreManager;
    let admin: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;

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
    });

    describe("constructor", function () {
        it("should set the contracts address correctly", async function () {
            expect(await core.contracts.factory.getAddress()).to.be.properAddress;
            expect(await core.contracts.storage.getAddress()).to.be.properAddress;
        });
    });

    describe("createAccount", function () {
        it("should create a dev account successfully", async function () {
            const accountName = "TestDev";

            const devManager = await core.devManager(accountName, user1);
            expect(devManager).to.not.be.undefined;

            const PublisherAccountAddress = await devManager["PublisherAccount"].getAddress();
            expect(PublisherAccountAddress).to.be.properAddress;
            expect(PublisherAccountAddress).to.not.equal(ethers.ZeroAddress);
        });

        it("should create different accounts for different users with same name", async function () {
            const accountName = "SameName";

            const devManager1 = await core.devManager(accountName, user1);
            const devManager2 = await core.devManager(accountName, user2);

            const address1 = await devManager1["PublisherAccount"].getAddress();
            const address2 = await devManager2["PublisherAccount"].getAddress();

            expect(address1).to.not.equal(address2);
        });

        it("should revert when creating account with empty name", async function () {
            const accountName = "";
            const factory = core.factoryFor(user1);

            await expect(
                factory["createAccount(string)"](accountName)
            ).to.be.revertedWithCustomError(await getFactory("PublisherAccount"), "PublisherAccountError")
                .withArgs(1);
        });

        it("should create account with very long name", async function () {
            const accountName = "A".repeat(1000);

            await expect(
                core.devManager(accountName, user1)
            ).to.be.revertedWithCustomError(await getFactory("PublisherAccount"), "PublisherAccountError")
                .withArgs(1);
        });

        it("should create account with special characters", async function () {
            const accountName = "Test-Dev_123!@#$%^&*()";

            const devManager = await core.devManager(accountName, user1);
            const PublisherAccount = devManager["PublisherAccount"];
            
            expect(await PublisherAccount.getName()).to.equal(accountName);
        });

        it("should revert when creating account with same name twice", async function () {
            const accountName = "DuplicateDev";
            
            await core.devManager(accountName, user1);

            const factory = core.factoryFor(user1);
            await expect(
                factory["createAccount(string)"](accountName)
            ).to.be.revertedWithCustomError(factory, "DevFactoryError")
                .withArgs(1);
        });

        it("should create multiple accounts with different names for same user", async function () {
            const names = ["Dev1", "Dev2", "Dev3"];
            const addresses: string[] = [];

            for (const name of names) {
                const devManager = await core.devManager(name, user1);
                const address = await devManager["PublisherAccount"].getAddress();
                addresses.push(address);
            }

            expect(addresses.length).to.equal(3);
            expect(new Set(addresses).size).to.equal(3);
        });

        it("should create valid PublisherAccount contract", async function () {
            const accountName = "ValidDev";

            const devManager = await core.devManager(accountName, user1);
            const PublisherAccount = devManager["PublisherAccount"];

            expect(await PublisherAccount.owner()).to.equal(user1.address);
            expect(await PublisherAccount.getName()).to.equal(accountName);
        });
    });

    describe("computeAccountAddress", function () {
        it("should return different addresses for different users", async function () {
            const accountName = "SameNameDifferentUser";

            const nameHash = id(accountName);
            const factory = core.contracts.factory;
            const address1 = await factory.computeAccountAddress(user1.address, nameHash);
            const address2 = await factory.computeAccountAddress(user2.address, nameHash);

            expect(address1).to.not.equal(address2);
            expect(address1).to.not.equal(ethers.ZeroAddress);
            expect(address2).to.not.equal(ethers.ZeroAddress);
        });
    });

    describe("events", function () {
        it("should emit PublisherAccountCreated event with correct parameters", async function () {
            const accountName = "EventTestDev";
            const factory = core.factoryFor(user1);

            await expect(factory["createAccount(string)"](accountName))
                .to.emit(factory, "PublisherAccountCreated")
                .withArgs(
                    user1.address,
                    function(address: string) { return address !== ethers.ZeroAddress; },
                    accountName,
                );
        });

        it("should emit events for multiple account creations", async function () {
            const factory = core.factoryFor(user1);
            const names = ["Event1", "Event2"];

            for (const name of names) {
                await expect(factory["createAccount(string)"](name))
                    .to.emit(factory, "PublisherAccountCreated")
                    .withArgs(user1.address, function(address: string) { return address !== ethers.ZeroAddress; }, name);
            }
        });
    });

    describe("constants", function () {
        it("should have correct DEV_ACCOUNT_PLUGINS constant", async function () {
            const expectedHash = ethers.id("openstore.plugins.default.PublisherAccount.v1");
            const actualHash = await core.contracts.factory.DEV_ACCOUNT_PLUGINS();

            expect(actualHash).to.equal(expectedHash);
        });
    });

    describe("edge cases and gas optimization", function () {
        it("should handle creating many accounts efficiently", async function () {
            const accountCount = 10;

            for (let i = 0; i < accountCount; i++) {
                await core.devManager(`Account${i}`, user1);
            }
        });

        it("should handle unicode characters in name", async function () {
            const unicodeName = "テスト開発者🚀";

            const devManager = await core.devManager(unicodeName, user1);
            const PublisherAccount = devManager["PublisherAccount"];
            
            expect(await PublisherAccount.getName()).to.equal(unicodeName);
        });

        it("should integrate with default configuration", async function () {
            const devName = Defaults.UserContractData.devName;

            const devManager = await core.devManager(devName, user1);
            const PublisherAccount = devManager["PublisherAccount"];
            
            expect(await PublisherAccount.getName()).to.equal(devName);
            expect(await PublisherAccount.owner()).to.equal(user1.address);
        });
    });
});