import {GfContracts, StoreConfig} from "./models";
import {AppGeneralInfoStruct} from "../typechain-types/contracts/app/AppAsset";
import {parseEther} from "ethers";

export const Defaults = {
    GreenfieldContracts: {
        BscTest: {
            executor: "0x3E3180883308e8B4946C9a485F8d91F8b15dC48e",
            permissionHub: "0x25E1eeDb5CaBf288210B132321FBB2d90b4174ad",
            tokenHub: "0xED8e5C546F84442219A5a987EE1D820698528E04",
            bucketHub: "0x5BB17A87D03620b313C39C24029C94cB5714814A",
            crossChain: "0xa5B2c9194131A4E0BFaCbF9E5D6722c873159cb7"
        } as GfContracts,
    },

    StoreConfig: {
        LH: {
            version: 1,
            minValidatorVersion: 1,

            isRequestsSuspended: false,
            isQueueSuspended: false,

            maxParallelProposals: 4,
            maxInactiveBlocks: 10,
            maxReqPerBlock: 128,

            validationRequestAmount: parseEther("0.1"),
            baseProposalAmount: parseEther("5"),
            baseVoteAmount: parseEther("1"),
            overdueProposalFee: parseEther("1"),
            inactiveFee: parseEther("1"),
            basicAmount: parseEther("4"),
            minStakeAmount: parseEther("5") + parseEther("5") + parseEther("2"),

            proposalBlockWindow: 60 * 10,
            voteBlockWindow: 60 * 10,
            minFinalizationWindow: 60 * 5,
        } as StoreConfig,

        BscTest: {
            version: 1,
            minValidatorVersion: 1,

            isRequestsSuspended: false,
            isQueueSuspended: false,

            maxParallelProposals: 4,
            maxInactiveBlocks: 10,
            maxReqPerBlock: 128,

            validationRequestAmount: parseEther("0.01"),
            baseProposalAmount: parseEther("0.1"),
            baseVoteAmount: parseEther("0.01"),
            overdueProposalFee: parseEther("0.015"),
            inactiveFee: parseEther("0.02"),
            basicAmount: parseEther("0.04"),
            minStakeAmount: parseEther("0.1") + parseEther("0.1") + parseEther("0.02"),

            proposalBlockWindow: 60 * 10,
            voteBlockWindow: 60 * 10,
            minFinalizationWindow: 60 * 5,
        } as StoreConfig
    },

    OracleFee: {
        LH: parseEther("0.005"),
        BscTest: parseEther("0.001"),
    },

    UserContractData: {
        devName: "KittyDev",
        owner: {
            proof: "0x54dadcb3b8d8dc0b42b0abc993ac91f94ba9a5c0010ffd5038d6c702a766a7147ef87bf3dd08402f3aec5fca16df9326a35853a550c6148f8f642d94e20574540822d0b3225f11d2dc6b063ff70b851c0270cc172139a2b0331c598b8cdb3f5730e9a510a6dde9fb6ff7355f739c8b93884ecbcd37442196e993fb188fec07dc1173c96bad25ec5227b2a2855c6d204cb5ab3f6828a2fe6c3776e93fb8375e5fa97ed46d2bee8298ac6faee009212bb5202e25be73cf8e153eb537539b606b45446cf33a117953d8f89acd15009b73e0afb2a49457af865d7d62eb6269f7af7f552464e45b26658b1938888b76d32c6ddeda5e4dcaaafe193b502b843f33f3a1",
            domain: "https://openstore.foundation",
            fingerprint: "0x21F955DAC405CBA21BBC269A328164E033ABFB2D93EA53417A458198F8ED5D82"
        },
        distribution: {
            link: "https://gnfd-testnet-sp2.bnbchain.org/view/kittydev/open-store-external/org_openstore_example_android/v/${VERSION_NAME}/${VERSION_CODE}.apk",
        },
        AppInfo: {
            id: "org.openstore.example.android",
            name: "Kitty App",
            description: "Some app description",
            protocolId: 1,
            platformId: 1,
            categoryId: 3,
        } as AppGeneralInfoStruct
    }
}
