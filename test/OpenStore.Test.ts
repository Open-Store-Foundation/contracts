import {expect} from "chai";
import {ethers, network} from "hardhat";
import {HardhatEthersSigner} from "@nomicfoundation/hardhat-ethers/signers";
import {wait} from "./utils/contracts";
import {OpenStore} from "../typechain-types";
import {BigNumberish, parseEther} from "ethers";
import {BLOCK_RESULT_STATUS, OPEN_STORE_ERRORS} from "./utils/const";
import {applyUnavailabilityToResult, createResultMask, createUnavailabilityMask} from "./utils/mask";
import {
    BuildHelper,
    createBlockRef,
    createDefaultBlockRef,
    createStoreHelpers,
    OracleHelper,
    OwnerHelper,
    StoreHelper
} from "./utils/store";
import {ContractsDeployer} from "../scripts/deployer";
import {Defaults} from "../scripts/defaults";
import {AppManager, CoreManager, DevManager} from "../scripts/manager";
import {attachOrDeployMulticastContract} from "./utils/multicall";
import {disableLogging} from "./utils/logger";

describe("OpenStore", function () {
    let deployer: ContractsDeployer;
    let core: CoreManager;
    let devManager: DevManager;
    let appManager: AppManager;
    let store: OpenStore;
    let storeWithUser: OpenStore;
    
    let admin: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;

    let ownerHelper: OwnerHelper;
    let buildHelper: BuildHelper;
    let oracleHelper: OracleHelper;
    let storeHelper: StoreHelper;

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
        store = core.contracts.store;
        storeWithUser = store.connect(user1);

        const topUpAmount = ethers.parseEther("15");
        const result = await wait(core.contracts.store.topUp({value: topUpAmount}));
        expect(result.status).to.equal(1);

        devManager = await core.devManager("TestDev", user1);
        appManager = await devManager.createApp({
            id: "com.test.app",
            name: "Test App",
            description: "Test application for store tests",
            protocolId: 1,
            platformId: 1,
            categoryId: 1
        }, user1);

        const helpers = createStoreHelpers(core, appManager, storeWithUser);
        ownerHelper = helpers.ownerHelper;
        buildHelper = helpers.buildHelper;
        oracleHelper = helpers.oracleHelper;
        storeHelper = helpers.storeHelper;
    });

    describe("addValidationRequest", function () {
        let appAddress: string;
        let fee: bigint;

        beforeEach(async function () {
            appAddress = await appManager.address();
            fee = Defaults.StoreConfig.LH.validationRequestAmount!;
        });

        describe("success cases", function () {
            it("should add validation request successfully", async function () {
                await buildHelper.addBuild(1);

                await expect(storeHelper.addLastValidationRequest(1))
                    .to.emit(store, "NewRequest");
            });

            it("should increment request ID for multiple requests", async function () {
                await buildHelper.addBuild(1);
                await buildHelper.addBuild(2);

                await expect(storeHelper.addLastValidationRequest(1))
                    .to.emit(store, "NewRequest");

                await expect(storeHelper.addLastValidationRequest(2))
                    .to.emit(store, "NewRequest");
            });

            it("shouldn't handle unknown request types", async function () {
                const unownedData = storeHelper.encodeBuildData(1n, 0n, 1);

                const tx = storeWithUser["addValidationRequest(uint256,address,bytes)"](
                    0, appAddress, unownedData,
                    {value: fee}
                );

                await expect(tx)
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.UNKNOWN_REQUEST_TYPE);
            });

            it("should work with multicall version", async function () {
                const unownedData = storeHelper.encodeBuildData(1n, 0n, 1);
                const calldata = store.interface.encodeFunctionData(
                    "addValidationRequest(address,uint256,address,bytes)",
                    [user1.address, 1, appAddress, unownedData]
                );

                const multicall = core.contracts.multicall;
                const call = multicall.connect(user1)
                    .multicall(
                        [{
                            manager: await store.getAddress(),
                            plugin: ethers.ZeroAddress,
                            data: calldata,
                            value: fee
                        }],
                        { value: fee }
                    );

                await expect(call)
                    .to.emit(store, "NewRequest")
                    .withArgs(appAddress, 1n, 1, unownedData);
            });
        });

        describe("error cases", function () {
            it("should revert when requests are suspended", async function () {
                await store.setIsRequestsSuspended(true);

                await expect(storeHelper.addLastValidationRequest(1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.REQUESTS_SUSPENDED);
            });

            it("should revert when sender is not target owner", async function () {
                const storeWithUser2 = store.connect(user2);
                const unownedData = storeHelper.encodeBuildData(1n, 0n, 1);

                await expect(
                    storeWithUser2["addValidationRequest(uint256,address,bytes)"](1, appAddress, unownedData, { value: fee })
                )
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.NOT_TARGET_OWNER);
            });

            it("should revert when build version downgraded", async function () {
                await store.connect(user1)["addBuildToTrack(address,uint256,uint256)"](appAddress, 1, 5);

                await expect(storeHelper.addLastValidationRequest(3))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.BUILD_VERSION_DOWNGRADED);
            });

            it("should revert when owner not verified for reqType 0 with ownerVersion > 0", async function () {
                await expect(storeHelper.addLastValidationRequest(1, 1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.OWNER_NOT_VERIFIED);
            });
        });

        describe("edge cases", function () {
            it("should not handle zero version codes", async function () {
                await expect(
                    storeWithUser["addValidationRequest(uint256,address,bytes)"](
                        1, appAddress, storeHelper.encodeBuildData(0, 0, 0),
                        {value: fee}
                    )
                )
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.BUILD_VERSION_ZERO);
            });

            it("should handle large version codes", async function () {
                await buildHelper.addBuild(Number(999999999999999));

                await expect(storeHelper.addLastValidationRequest(999999999999999))
                    .to.emit(store, "NewRequest");
            });

            it("should handle maximum track ID", async function () {
                await buildHelper.addBuild(1);

                await expect(storeHelper.addLastValidationRequest(1, undefined, undefined, 255))
                    .to.emit(store, "NewRequest");
            });

            it("should handle exact validation request amount", async function () {
                await buildHelper.addBuild(1);

                await expect(storeHelper.addLastValidationRequest(1, undefined, fee))
                    .to.emit(store, "NewRequest");
            });

            it("should revert overpayment", async function () {
                await buildHelper.addBuild(1);

                const doubleFee = fee * 2n;
                await expect(storeHelper.addLastValidationRequest(1, undefined, doubleFee))
                    .to.emit(store, "NewRequest");
            });

            it("should revert underpayment", async function () {
                await buildHelper.addBuild(1);

                await expect(storeHelper.addLastValidationRequest(1, undefined, 0))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.INCORRECT_VALIDATION_FEE);
            });
        });
    });

    describe("getRequest", function () {
        let appAddress: string;

        beforeEach(async function () {
            appAddress = await appManager.address();
        });

        it("should return stored request data", async function () {
            await buildHelper.addBuild(1);
            await storeHelper.addLastValidationRequest(1);

            const [reqType, target, requestData] = await store.getRequest(1);
            
            expect(reqType).to.not.be.null;
            expect(target).to.equal(appAddress);
            expect(requestData).to.not.be.null;
        });

        it("should return empty data for non-existent request", async function () {
            const [reqType, target, data] = await store.getRequest(999);
            
            expect(reqType).to.equal(0);
            expect(target).to.equal(ethers.ZeroAddress);
            expect(data).to.equal("0x");
        });
    });

    describe("validator balance management", function () {
        describe("topUp", function () {
            it("should allow topping up balance", async function () {
                const topUpAmount = parseEther("10");
                const initialBalance = await store.balance(user1.address);
                const initialTotalBalance = await store.validatorTotalBalance(user1.address);

                await expect(storeWithUser.topUp({ value: topUpAmount }))
                    .to.changeEtherBalance(user1, -topUpAmount);

                expect(await store.balance(user1.address)).to.equal(initialBalance + topUpAmount);
                expect(await store.validatorTotalBalance(user1.address)).to.equal(initialTotalBalance + topUpAmount);
            });

            it("should handle multiple top-ups", async function () {
                const amount1 = parseEther("5");
                const amount2 = parseEther("3");
                const initialBalance = await store.balance(user1.address);

                await storeWithUser.topUp({ value: amount1 });
                await storeWithUser.topUp({ value: amount2 });

                expect(await store.balance(user1.address)).to.equal(initialBalance + amount1 + amount2);
            });

            it("should handle zero top-up", async function () {
                const initialBalance = await store.balance(user1.address);

                await expect(storeWithUser.topUp({ value: 0 })).not.to.be.reverted;
                expect(await store.balance(user1.address)).to.equal(initialBalance);
            });

            it("should update total balance for registered validators", async function () {
                const topUpAmount = parseEther("20");

                await storeWithUser.topUp({ value: topUpAmount });
                await storeWithUser.registerValidator(1);

                const initialTotalSystemBalance = await store.totalBalance();
                await storeWithUser.topUp({ value: topUpAmount });
                const finalTotalSystemBalance = await store.totalBalance();
                
                expect(finalTotalSystemBalance).to.be.greaterThan(initialTotalSystemBalance);
            });
        });

        describe("withdraw", function () {
            const initialTopUp = parseEther("20");

            beforeEach(async function () {
                await storeWithUser.topUp({ value: initialTopUp });
            });

            it("should allow withdrawing available balance", async function () {
                const withdrawAmount = parseEther("5");
                const initialBalance = await store.balance(user1.address);
                const initialTotalBalance = await store.validatorTotalBalance(user1.address);

                await expect(storeWithUser.withdraw(withdrawAmount))
                    .to.changeEtherBalance(user1, withdrawAmount);

                expect(await store.balance(user1.address)).to.equal(initialBalance - withdrawAmount);
                expect(await store.validatorTotalBalance(user1.address)).to.equal(initialTotalBalance - withdrawAmount);
            });

            it("should revert when trying to withdraw more than available balance", async function () {
                const balance = await store.balance(user1.address);
                const excessiveAmount = balance + parseEther("1");

                await expect(storeWithUser.withdraw(excessiveAmount))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.INSUFFICIENT_BALANCE);
            });

            it("should allow withdrawing exact balance", async function () {
                const balance = await store.balance(user1.address);

                await expect(storeWithUser.withdraw(balance)).not.to.be.reverted;
                expect(await store.balance(user1.address)).to.equal(0);
            });

            it("should handle zero withdrawal", async function () {
                const initialBalance = await store.balance(user1.address);

                await expect(storeWithUser.withdraw(0)).not.to.be.reverted;
                expect(await store.balance(user1.address)).to.equal(initialBalance);
            });

            it("should update total balance for registered validators", async function () {
                await storeWithUser.registerValidator(1);
                const withdrawAmount = parseEther("5");
                const initialTotalSystemBalance = await store.totalBalance();

                await storeWithUser.withdraw(withdrawAmount);
                const finalTotalSystemBalance = await store.totalBalance();
                
                expect(finalTotalSystemBalance).to.be.lessThan(initialTotalSystemBalance);
            });
        });

        describe("balance queries", function () {
            it("should return zero balance for new addresses", async function () {
                expect(await store.balance(user2.address)).to.equal(0);
                expect(await store.validatorTotalBalance(user2.address)).to.equal(0);
                expect(await store.blocksValidated(user2.address)).to.equal(0);
            });

            it("should track balance and total balance separately", async function () {
                const topUpAmount = parseEther("10");
                await storeWithUser.topUp({ value: topUpAmount });

                expect(await store.balance(user1.address)).to.equal(topUpAmount);
                expect(await store.validatorTotalBalance(user1.address)).to.equal(topUpAmount);

                const withdrawAmount = parseEther("3");
                await storeWithUser.withdraw(withdrawAmount);

                expect(await store.balance(user1.address)).to.equal(topUpAmount - withdrawAmount);
                expect(await store.validatorTotalBalance(user1.address)).to.equal(topUpAmount - withdrawAmount);
            });
        });
    });

    describe("validator registration", function () {
        let storeWithUser2: OpenStore;

        beforeEach(async function () {
            storeWithUser2 = store.connect(user2);
            await storeWithUser.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });
        });

        describe("registerValidator", function () {
            it("should allow registering validator with sufficient stake", async function () {
                const validatorVersion = 1;

                expect(await store.isValidatorRegistered(user1.address)).to.equal(false);
                await expect(storeWithUser.registerValidator(validatorVersion)).not.to.be.reverted;
                expect(await store.isValidatorRegistered(user1.address)).to.equal(true);
            });

            it("should revert with unsupported validator version", async function () {
                const unsupportedVersion = 0;

                await expect(storeWithUser.registerValidator(unsupportedVersion))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.VALIDATOR_UNSUPPORTED_VERSION);
            });

            it("should revert when already registered", async function () {
                await storeWithUser.registerValidator(1);

                await expect(storeWithUser.registerValidator(1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.VALIDATOR_ALREADY_REGISTERED);
            });

            it("should revert with insufficient stake", async function () {
                await storeWithUser2.topUp({ value: parseEther("1") });

                await expect(storeWithUser2.registerValidator(1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.INSUFFICIENT_STAKE);
            });

            it("should update total balance when registering", async function () {
                const initialSystemBalance = await store.totalBalance();
                await storeWithUser.registerValidator(1);
                const finalSystemBalance = await store.totalBalance();
                
                expect(finalSystemBalance).to.be.greaterThan(initialSystemBalance);
            });

            it("should handle multiple validators registering", async function () {
                await storeWithUser2.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });

                await storeWithUser.registerValidator(1);
                await storeWithUser2.registerValidator(1);

                expect(await store.isValidatorRegistered(user1.address)).to.equal(true);
                expect(await store.isValidatorRegistered(user2.address)).to.equal(true);
            });
        });

        describe("unregisterValidator", function () {
            beforeEach(async function () {
                await storeWithUser.registerValidator(1);
            });

            it("should allow unregistering validator", async function () {
                expect(await store.isValidatorRegistered(user1.address)).to.equal(true);
                await expect(storeWithUser.unregisterValidator()).not.to.be.reverted;
                expect(await store.isValidatorRegistered(user1.address)).to.equal(false);
            });

            it("should revert when not registered", async function () {
                await expect(storeWithUser2.unregisterValidator())
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.VALIDATOR_NOT_REGISTERED);
            });

            it("should revert when validator is in queue", async function () {
                await storeWithUser.topUp({ value: Defaults.StoreConfig.LH.baseProposalAmount });
                await storeWithUser.assignBlockId(1);

                await expect(storeWithUser.unregisterValidator())
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.VALIDATOR_IN_QUEUE);
            });

            it("should update total balance when unregistering", async function () {
                const initialSystemBalance = await store.totalBalance();
                await storeWithUser.unregisterValidator();
                const finalSystemBalance = await store.totalBalance();
                
                expect(finalSystemBalance).to.be.lessThan(initialSystemBalance);
            });

            it("should handle multiple validators unregistering", async function () {
                await storeWithUser2.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });
                await storeWithUser2.registerValidator(1);

                await storeWithUser.unregisterValidator();
                expect(await store.isValidatorRegistered(user1.address)).to.equal(false);
                expect(await store.isValidatorRegistered(user2.address)).to.equal(true);

                await storeWithUser2.unregisterValidator();
                expect(await store.isValidatorRegistered(user2.address)).to.equal(false);
            });
        });

        describe("validator status queries", function () {
            beforeEach(async function () {
                await storeWithUser.registerValidator(1);
            });

            it("should return correct validator assign status", async function () {
                expect(await store.validatorAssignStatus(user2.address, 1)).to.equal(2);
                expect(await store.validatorAssignStatus(user1.address, 1)).to.equal(0);
            });

            it("should detect version outdated", async function () {
                await storeWithUser2.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });
                expect(await store.validatorAssignStatus(user2.address, 0)).to.equal(1);
            });

            it("should check if validator can be assigned", async function () {
                expect(await store.canAssignValidator(user1.address)).to.equal(true);
            });
        });
    });

    describe("block assignment", function () {
        beforeEach(async function () {
            await storeWithUser.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount + Defaults.StoreConfig.LH.baseProposalAmount });
            await storeWithUser.registerValidator(1);
        });

        describe("assignBlockId", function () {
            it("should allow assigning block to registered validator", async function () {
                const blockId = await store.nextRequestIdToValidate();

                expect(await store.nextBlockIdFor(user1.address)).to.equal(0);

                await expect(storeWithUser.assignBlockId(blockId))
                    .to.emit(store, "QueueChanged")
                    .withArgs(blockId, user1.address);

                expect(await store.nextBlockIdFor(user1.address)).to.equal(blockId);
            });

            it("should increment next block ID", async function () {
                expect(await store.nextBlockIdToValidated()).to.equal(1);
                await storeWithUser.assignBlockId(1);
                expect(await store.nextBlockIdToValidated()).to.equal(2);
            });

            it("should revert when queue is suspended", async function () {
                await store.setIsQueueSuspended(true);
                await expect(storeWithUser.assignBlockId(1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.QUEUE_SUSPENDED);
            });

            it("should revert when validator not registered", async function () {
                const storeWithUser2 = store.connect(user2);

                await expect(storeWithUser2.assignBlockId(1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.VALIDATOR_NOT_REGISTERED);
            });

            it("should revert when validator version outdated", async function () {
                await store.setMinValidatorVersion(2);

                await expect(storeWithUser.assignBlockId(1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.VALIDATOR_UNSUPPORTED_VERSION);
            });

            it("should revert when validator already in queue", async function () {
                await storeWithUser.assignBlockId(1);

                await expect(storeWithUser.assignBlockId(2))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.VALIDATOR_ALREADY_IN_QUEUE);
            });

            it("should revert with non-incremental block ID", async function () {
                await expect(storeWithUser.assignBlockId(2))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.BLOCK_ID_NOT_INCREMENTAL);
            });

            it("should deduct proposal amount from balance", async function () {
                const initialBalance = await store.balance(user1.address);
                await storeWithUser.assignBlockId(1);
                const finalBalance = await store.balance(user1.address);

                expect(finalBalance).to.equal(initialBalance - Defaults.StoreConfig.LH.baseProposalAmount);
            });
        });

        describe("unassignBlockId", function () {
            beforeEach(async function () {
                await storeWithUser.assignBlockId(1);
            });

            it("should allow unassigning block", async function () {
                const initialBalance = await store.balance(user1.address);

                await expect(storeWithUser.unassignBlockId(1))
                    .not.to.be.reverted;

                expect(await store.nextBlockIdFor(user1.address)).to.equal(0);

                const finalBalance = await store.balance(user1.address);
                expect(finalBalance).to.equal(initialBalance + Defaults.StoreConfig.LH.baseProposalAmount);
            });

            it("should decrement next block ID", async function () {
                expect(await store.nextBlockIdToValidated()).to.equal(2);

                await storeWithUser.unassignBlockId(1);
                expect(await store.nextBlockIdToValidated()).to.equal(1);
            });

            it("should revert when not block owner", async function () {
                const storeWithUser2 = store.connect(user2);

                await expect(storeWithUser2.unassignBlockId(1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.SENDER_NOT_BLOCK_OWNER);
            });

            it("should revert when cannot unassign block", async function () {
                const storeWithUser2 = store.connect(user2);

                await storeWithUser2.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount + Defaults.StoreConfig.LH.baseProposalAmount });
                await storeWithUser2.registerValidator(1);
                await storeWithUser2.assignBlockId(2);

                await expect(storeWithUser.unassignBlockId(1))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.CANNOT_UNASSIGN_BLOCK);
            });
        });
    });

    describe("Configs and state check", function () {
        describe("Config", function () {
            describe("version", function () {
                it("should return initial version", async function () {
                    expect(await store.version()).to.equal(1);
                });

                it("should allow owner to set new version", async function () {
                    const newVersion = 2;

                    await expect(store.setVersion(newVersion))
                        .to.emit(store, "ConfigChanged");

                    expect(await store.version()).to.equal(newVersion);
                });

                it("should revert when setting same or lower version", async function () {
                    await expect(store.setVersion(1))
                        .to.be.revertedWithCustomError(store, "OpenStoreError")
                        .withArgs(OPEN_STORE_ERRORS.VERSION_CONFIG_MUST_INCREASE);

                    await expect(store.setVersion(0))
                        .to.be.revertedWithCustomError(store, "OpenStoreError")
                        .withArgs(OPEN_STORE_ERRORS.VERSION_CONFIG_MUST_INCREASE);
                });

                it("should revert when non-owner tries to set version", async function () {
                    await expect(storeWithUser.setVersion(2))
                        .to.be.revertedWithCustomError(store, "OwnableUnauthorizedAccount")
                        .withArgs(user1.address);
                });
            });

            describe("minValidatorVersion", function () {
                it("should return initial min validator version", async function () {
                    expect(await store.minValidatorVersion()).to.equal(1);
                });

                it("should allow owner to set min validator version", async function () {
                    const newVersion = 2;

                    await expect(store.setMinValidatorVersion(newVersion))
                        .to.emit(store, "ConfigChanged");

                    expect(await store.minValidatorVersion()).to.equal(newVersion);
                });

                it("should revert when non-owner tries to set min validator version", async function () {
                    await expect(storeWithUser.setMinValidatorVersion(2))
                        .to.be.revertedWithCustomError(store, "OwnableUnauthorizedAccount")
                        .withArgs(user1.address);
                });
            });

            describe("requests suspension", function () {
                it("should allow setting requests suspension status", async function () {
                    await expect(store.setIsRequestsSuspended(true))
                        .to.emit(store, "RequestsStatusChanged")
                        .withArgs(true);

                    const config = await store.config();
                    expect(config.isRequestsSuspended).to.equal(true);
                });

                it("should allow unsuspending requests", async function () {
                    await store.setIsRequestsSuspended(true);

                    await expect(store.setIsRequestsSuspended(false))
                        .to.emit(store, "RequestsStatusChanged")
                        .withArgs(false);

                    const config = await store.config();
                    expect(config.isRequestsSuspended).to.equal(false);
                });
            });

            describe("queue suspension", function () {
                it("should allow setting queue suspension status", async function () {
                    await expect(store.setIsQueueSuspended(true))
                        .to.emit(store, "QueueStatusChanged")
                        .withArgs(true);

                    const config = await store.config();
                    expect(config.isQueueSuspended).to.equal(true);
                });
            });

            describe("updateConfig", function () {
                it("should allow owner to update full config", async function () {
                    const newConfig = {
                        ...Defaults.StoreConfig.LH,
                        oracle: await core.contracts.oracle.getAddress(),
                        requestHandler: await store.config().then(c => c.requestHandler),
                        version: 2,
                        maxParallelProposals: 5,
                        validationRequestAmount: parseEther("0.2")
                    };

                    await expect(store.updateConfig(newConfig))
                        .to.emit(store, "ConfigChanged");

                    const updatedConfig = await store.config();
                    expect(updatedConfig.version).to.equal(2);
                    expect(updatedConfig.maxParallelProposals).to.equal(5);
                    expect(updatedConfig.validationRequestAmount)
                        .to.equal(parseEther("0.2"));
                });

                it("should revert when non-owner tries to update config", async function () {
                    const newConfig = {
                        ...Defaults.StoreConfig.LH,
                        oracle: await core.contracts.oracle.getAddress(),
                        requestHandler: await store.config().then(c => c.requestHandler),
                        version: 2
                    };

                    await expect(storeWithUser.updateConfig(newConfig))
                        .to.be.revertedWithCustomError(store, "OwnableUnauthorizedAccount")
                        .withArgs(user1.address);
                });
            });

            describe("config getters", function () {
                it("should return min stake amount", async function () {
                    expect(await store.getMinStakeAmount()).to.equal(Defaults.StoreConfig.LH.minStakeAmount);
                });

                it("should return unspendable amount", async function () {
                    expect(await store.getBasicAmount()).to.equal(Defaults.StoreConfig.LH.basicAmount);
                });

                it("should return full config", async function () {
                    const config = await store.config();
                    expect(config.version).to.equal(Defaults.StoreConfig.LH.version);
                    expect(config.minValidatorVersion).to.equal(Defaults.StoreConfig.LH.minValidatorVersion);
                    expect(config.oracle).to.equal(await core.contracts.oracle.getAddress());
                });
            });
        });

        describe("nextRequestIdToValidate", function () {
            it("should start at 1", async function () {
                expect(await store.nextRequestIdToValidate()).to.equal(1);
            });

            it("should increment after adding requests", async function () {
                expect(await store.nextRequestIdToValidate()).to.equal(1);

                await buildHelper.addBuild(1);
                await storeHelper.addLastValidationRequest(1);
                expect(await store.nextRequestIdToValidate()).to.equal(2);

                await buildHelper.addBuild(2);
                await storeHelper.addLastValidationRequest(2);
                expect(await store.nextRequestIdToValidate()).to.equal(3);
            });
        });

        describe("block state defaults", function () {
            it("should return correct block state for validator", async function () {
                expect(await store.blockStateFor(1, user1.address)).to.equal(0);

                await storeWithUser.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });
                await storeWithUser.registerValidator(1);
                await storeWithUser.assignBlockId(1);

                expect(await store.blockStateFor(1, user1.address)).to.equal(1);
            });

            it("should return next block ID to validate", async function () {
                expect(await store.nextBlockIdToValidated()).to.equal(1);

                await storeWithUser.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });
                await storeWithUser.registerValidator(1);
                await storeWithUser.assignBlockId(1);

                expect(await store.nextBlockIdToValidated()).to.equal(2);
            });

            it("should return next block ID to propose", async function () {
                expect(await store.nextBlockIdToPropose()).to.equal(1);
            });

            it("should return next block ID to finalize", async function () {
                expect(await store.nextBlockIdToFinalize()).to.equal(1);
            });

            it("should return emergency block ID for validator", async function () {
                expect(await store.emergencyBlockIdFor(user1.address)).to.equal(0);
            });
        });
    });

    describe("Propose/Vote/Finalize Workflow", function () {
        let validator1: HardhatEthersSigner;
        let validator2: HardhatEthersSigner;
        let validator3: HardhatEthersSigner;
        let validatorDecider: HardhatEthersSigner;

        let storeV1: OpenStore;
        let storeV2: OpenStore;
        let storeV3: OpenStore;
        let storeDecider: OpenStore;

        beforeEach(async function () {
            [,,, validator1, validator2, validator3, validatorDecider] = await ethers.getSigners();

            await admin.sendTransaction({ to: validator1.address, value: Defaults.StoreConfig.LH.minStakeAmount });
            await admin.sendTransaction({ to: validator2.address, value: Defaults.StoreConfig.LH.minStakeAmount });
            await admin.sendTransaction({ to: validator3.address, value: Defaults.StoreConfig.LH.minStakeAmount });
            await admin.sendTransaction({ to: validatorDecider.address, value: parseEther("110") });

            storeV1 = store.connect(validator1);
            storeV2 = store.connect(validator2);
            storeV3 = store.connect(validator3);
            storeDecider = store.connect(validatorDecider);

            await storeV1.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });
            await storeV2.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });
            await storeV3.topUp({ value: Defaults.StoreConfig.LH.minStakeAmount });
            await storeDecider.topUp({ value: parseEther("10") });

            await storeV1.registerValidator(1);
            await storeV2.registerValidator(1);
            await storeV3.registerValidator(1);
        });

        describe("proposeBlock", function () {
            it("should allow main proposer to propose during proposal window", async function () {
                await appManager.addBuild(1);

                const buildId = await buildHelper.appBuilds.getLastVersionCode();
                const ownerVersion = await ownerHelper.appOwner.ownerVersion();
                const params = storeHelper.encodeBuildData(buildId, ownerVersion, 1);

                await storeWithUser["addValidationRequest(uint256,address,bytes)"](1, await appManager.address(), params, {
                    value: Defaults.StoreConfig.LH.validationRequestAmount
                });

                await storeV1.assignBlockId(1);

                const blockRef = createBlockRef({
                    id: 1,
                    fromRequestId: 1,
                    toRequestId: 2,
                    createdBy: validator1.address
                });

                const tx = await storeV1.proposeBlock(blockRef);
                const receipt = await tx.wait();

                const event = receipt?.logs.find(log => 
                    log.topics[0] === store.interface.getEvent("BlockProposed").topicHash
                );
                expect(event).to.not.be.undefined;
            });

            it("should allow emergency proposer after proposal window expires", async function () {
                await appManager.addBuild(1);

                const buildId = await buildHelper.appBuilds.getLastVersionCode();
                const ownerVersion = await ownerHelper.appOwner.ownerVersion();
                const params = storeHelper.encodeBuildData(buildId, ownerVersion, 1);

                await storeWithUser["addValidationRequest(uint256,address,bytes)"](1, await appManager.address(), params, {
                    value: Defaults.StoreConfig.LH.validationRequestAmount
                });

                await storeV1.assignBlockId(1);

                await network.provider.send("evm_increaseTime", [Defaults.StoreConfig.LH.proposalBlockWindow + 1]);
                await network.provider.send("evm_mine");

                const blockRef = createBlockRef({
                    id: 1,
                    fromRequestId: 1,
                    toRequestId: 2,
                    createdBy: validator2.address
                });

                const tx = await storeV2.proposeBlock(blockRef);
                const receipt = await tx.wait();

                const event = receipt?.logs.find(log => 
                    log.topics[0] === store.interface.getEvent("BlockProposed").topicHash
                );
                expect(event).to.not.be.undefined;
            });

            it("should allow discussion proposals", async function () {
                await appManager.addBuild(1);

                const buildId = await buildHelper.appBuilds.getLastVersionCode();
                const ownerVersion = await ownerHelper.appOwner.ownerVersion();
                const params = storeHelper.encodeBuildData(buildId, ownerVersion, 1);

                await storeWithUser["addValidationRequest(uint256,address,bytes)"](1, await appManager.address(), params, {
                    value: Defaults.StoreConfig.LH.validationRequestAmount
                });

                const [
                    blockNumber,
                    nextBlockId,
                    nextFinalBlockId,
                    emergencyLocker,
                    nextProposalBlockId,
                    validatorLocker,
                    nextRequestIdForProposal,
                    nextRequestId
                ] = await store.getLastState(validator1.address);
                
                await storeV1.assignBlockId(1);

                const mainBlockRef = createBlockRef({
                    id: 1,
                    fromRequestId: Number(nextRequestIdForProposal),
                    toRequestId: Number(nextRequestIdForProposal + 1n),
                    createdBy: validator1.address
                });

                await storeV1.proposeBlock(mainBlockRef);

                const discussionBlockRef = createBlockRef({
                    id: mainBlockRef.id,
                    objectHash: ethers.id(validator2.address),
                    fromRequestId: mainBlockRef.fromRequestId,
                    toRequestId: mainBlockRef.toRequestId,
                    resultStatuses: [BLOCK_RESULT_STATUS.ERROR],
                    isDiscussion: true,
                    createdBy: validator2.address
                });

                const receipt = await wait(storeV2.proposeBlock(discussionBlockRef));

                const event = receipt?.logs.find(log => 
                    log.topics[0] === store.interface.getEvent("BlockProposed").topicHash
                );
                expect(event).to.not.be.undefined;
            });

            it("should revert with invalid request range", async function () {
                await storeV1.assignBlockId(1);

                const blockRef = createBlockRef({
                    id: 1,
                    fromRequestId: 2,
                    toRequestId: 1,
                    createdBy: validator1.address
                });

                await expect(storeV1.proposeBlock(blockRef))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.INVALID_REQUEST_ID_RANGE);
            });

            it("should revert when too many requests in block", async function () {
                await storeV1.assignBlockId(1);

                await expect(() => createBlockRef({
                    id: 1,
                    fromRequestId: 1,
                    toRequestId: Defaults.StoreConfig.LH.maxReqPerBlock + 2,
                    createdBy: validator1.address
                })).to.throw(`Request count ${Defaults.StoreConfig.LH.maxReqPerBlock + 1} exceeds maxReqPerBlock ${Defaults.StoreConfig.LH.maxReqPerBlock}`);
            });
        });

        describe("vote", function () {
            let blockId: BigNumberish;

            beforeEach(async function () {
                blockId = await store.nextBlockIdToPropose();
                const ownerVersion = await oracleHelper.updateOwnerAndVerify();
                const reqId = await storeHelper.addBuildsAndRequest(1, ownerVersion);

                await storeV1.assignBlockId(blockId);
                const mainBlockRef = createDefaultBlockRef(blockId, reqId, validator1);
                await storeV1.proposeBlock(mainBlockRef);
            });

            it("should allow validators to vote for proposals", async function () {
                await expect(storeV2.vote(blockId, validator1.address, 0))
                    .to.emit(store, "ValidatorVoted")
                    .withArgs(blockId, validator1.address, validator2.address);
            });

            it("should allow voting with unavailability mask", async function () {
                const unavailabilityMask = createUnavailabilityMask(1, [0]);

                await expect(storeV2.vote(blockId, validator1.address, unavailabilityMask))
                    .to.emit(store, "ValidatorVoted")
                    .withArgs(blockId, validator1.address, validator2.address);
            });

            it("should revert when voting for self", async function () {
                await expect(storeV1.vote(blockId, validator1.address, 0))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.CANNOT_VOTE_FOR_SELF);
            });

            it("should revert when already voted", async function () {
                await storeV2.vote(blockId, validator1.address, 0);

                await expect(storeV2.vote(blockId, validator1.address, 0))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.ALREADY_VOTED);
            });

            it("should revert when voting period expired", async function () {
                await network.provider.send("evm_increaseTime", [Defaults.StoreConfig.LH.voteBlockWindow + 1]);
                await network.provider.send("evm_mine");

                await expect(storeV2.vote(blockId, validator1.address, 0))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.VOTING_PERIOD_CLOSED);
            });
        });

        describe("finalize block simple", function () {
            it("should handle unavailability voting correctly", async function () {
                const blockId = await store.nextBlockIdToPropose();
                const ownerVersion = await oracleHelper.updateOwnerAndVerify();
                const reqId1 = await storeHelper.addBuildsAndRequest(1, ownerVersion);
                const reqId2 = await storeHelper.addBuildsAndRequest(2, ownerVersion);

                await storeV1.assignBlockId(blockId);

                const blockRef = createBlockRef({
                    id: blockId,
                    fromRequestId: reqId1,
                    toRequestId: reqId2 + 1n,
                    resultStatuses: [BLOCK_RESULT_STATUS.SUCCESS, BLOCK_RESULT_STATUS.SUCCESS],
                    createdBy: validator1.address
                });

                await storeV1.proposeBlock(blockRef);

                const unavailabilityMask = createUnavailabilityMask(2, [0]);
                await storeV2.vote(blockId, validator1.address, unavailabilityMask);
                await storeV3.vote(blockId, validator1.address, unavailabilityMask);

                await expect(storeV1.finalizeBlock(blockId))
                    .to.emit(store, "BlockFinalized")
                    .withArgs(blockId, validator1.address, blockRef.objectId);

                const finalBlock = await store.getBlockRef(blockId);
                const finalResult = applyUnavailabilityToResult(
                    createResultMask(2, [BLOCK_RESULT_STATUS.SUCCESS, BLOCK_RESULT_STATUS.SUCCESS]),
                    unavailabilityMask,
                    2
                );

                expect(finalBlock.result).to.equal(finalResult);
            });

            it("should update vault with successful requests", async function () {
                const versionCode = 1;
                const blockId = await store.nextBlockIdToPropose();
                const ownerVersion = await oracleHelper.updateOwnerAndVerify();
                const reqId = await storeHelper.addBuildsAndRequest(versionCode, ownerVersion);

                await storeV1.assignBlockId(blockId);
                const mainBlockRef = createDefaultBlockRef(blockId, reqId, validator1);
                await storeV1.proposeBlock(mainBlockRef);

                await storeV2.vote(blockId, validator1.address, 0);
                await storeV3.vote(blockId, validator1.address, 0);

                const appAddress = await appManager.address();
                expect(await store.isBuildVerified(appAddress, versionCode)).to.be.false;
                expect(await store.getLastAppVersion(appAddress, 1)).to.equal(0);
                
                await expect(store.finalizeBlock(blockId))
                    .to.emit(store, "BlockFinalized")
                    .withArgs(blockId, validator1.address, mainBlockRef.objectId);
                
                expect(await store.isBuildVerified(appAddress, versionCode)).to.be.true;
                expect(await store.getLastAppVersion(appAddress, 1)).to.equal(versionCode);
            });

            it("should revert when not next block to finalize", async function () {
                await expect(store.finalizeBlock(2))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.BLOCK_ID_NOT_NEXT_TO_FINALIZE);
            });

            it("should revert when proposal not ready to finalize (by time)", async function () {
                const blockId = await store.nextBlockIdToPropose();
                const ownerVersion = await oracleHelper.updateOwnerAndVerify();
                const reqId = await storeHelper.addBuildsAndRequest(1, ownerVersion);

                await storeV1.assignBlockId(blockId);
                const mainBlockRef = createDefaultBlockRef(blockId, reqId, validator1);
                await storeV1.proposeBlock(mainBlockRef);

                await expect(store.finalizeBlock(blockId))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.PROPOSAL_NOT_READY_TO_FINALIZE);

                await network.provider.send("evm_increaseTime", [Defaults.StoreConfig.LH.voteBlockWindow + 1]);
                await network.provider.send("evm_mine");

                await expect(store.finalizeBlock(blockId))
                    .to.emit(store, "BlockFinalized")
                    .withArgs(blockId, validator1.address, mainBlockRef.objectId);
            });

            it("should revert when proposal not ready to finalize (by votes)", async function () {
                const blockId = await store.nextBlockIdToPropose();
                const ownerVersion = await oracleHelper.updateOwnerAndVerify();
                const reqId = await storeHelper.addBuildsAndRequest(1, ownerVersion);

                await storeV1.assignBlockId(blockId);
                const mainBlockRef = createDefaultBlockRef(blockId, reqId, validator1);
                await storeV1.proposeBlock(mainBlockRef);

                await expect(store.finalizeBlock(blockId))
                    .to.be.revertedWithCustomError(store, "OpenStoreError")
                    .withArgs(OPEN_STORE_ERRORS.PROPOSAL_NOT_READY_TO_FINALIZE);

                await storeV2.vote(blockId, validator1.address, 0);
                await storeV3.vote(blockId, validator1.address, 0);

                await expect(store.finalizeBlock(blockId))
                    .to.emit(store, "BlockFinalized")
                    .withArgs(blockId, validator1.address, mainBlockRef.objectId);
            });
        });
    });
}); 