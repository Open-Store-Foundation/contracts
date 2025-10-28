import {GfContracts, StoreConfig} from "./models";
import {AppGeneralInfoStruct} from "../typechain-types/contracts/app/AppAsset";
import {parseEther} from "ethers";

export const Defaults = {
    Ids: {
        APP_PLUGINS: "openstore.plugins.default.AppAsset.v1",
        PUBLISHER_PLUGINS: "openstore.plugins.default.PublisherAccount.v1",
    },

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
            cert: "0x3082032830820210020101300d06092a864886f70d01010b0500305a310d300b06035504030c0474657374310d300b060355040b0c0474657374310d300b060355040a0c0474657374310d300b06035504070c0474657374310d300b06035504080c0474657374310d300b0603550406130474657374301e170d3234303131333134313733385a170d3439303130363134313733385a305a310d300b06035504030c0474657374310d300b060355040b0c0474657374310d300b060355040a0c0474657374310d300b06035504070c0474657374310d300b06035504080c0474657374310d300b060355040613047465737430820122300d06092a864886f70d01010105000382010f003082010a0282010100c64d25e48e33fc63024744ddbe50f8cea55f92a0bd4fc81ae9a972a5a1fc9f19314af1054868ea217b472e42193d6c893caa4f88f03d517aec193367cbec7cde24877e76d3a48cb1008a32752879882a17220811a4f264e0dbbf71f1a1134fd8ca42a92c99e3c2b048cc18fd8934e7d601e54bbcdfe335a86432c171b1b210d5d518a6b2df6df5750a5969385e498cf55ad22b842652c5772d67004c8a13282f22398d749423cf1dce4d2ac3b3f7f186103228baba9dc98ae8053d54a8ffe8db48e65b11981142ba211367574a856897efe77093d17e6852fc0b5a5d4cc5835ec635357ae209ff0a91ed8a78e3808998177d441c35774bcaf2737c5285118bab0203010001300d06092a864886f70d01010b05000382010100adc880355126add9e4277d83ded06056b13e34a38136ba1746d70e81504dd2bb5bad7d9f31286d85a1f8c1ae5d2e79939e209081ff8754fe7860fcf0fce05d667120b89784fc25243278bcaee92df71efd07553417275be644180d4b1b272f65cc4a9cc5d28ceb7fa0f76a064b26e599bdafcf676140c60bca0d9ba0185d2031d7533549bf656883f4deca6d1c3edc2ff85c1b76ccc994f1b88a21d58f74118a27fdae26c5a4d74293f16a35cb6b233b8b37f968d1f0e34ff32dbe6e41e4e2eb3829cf18d1da8c9f761871c8556173154f983278d2d8a7869a9f2bbe0b5c6e48fe32507e4fb6ddf73d02e703bc800e3f4466febfec89b50007df4d43c347f529",
            proof: "0x286695d1299ba6a508a72678db2d57e2a7712a29fb0e4902119167b328e78ef6c908218e44332819a8f4fd86ec26ab933ee0a3a6eb444ac588f6656e0f884b26c44f83ff7d155d9380a09ca38983992c87336f952cda856f06aa3da82826329a585a63b986267281fb6e62cf822b9940a5cfe5adb9eb47c4bf6582b36262597147a03203ec629c737286a71bc209d9e3fd1a3874eb0aa302fa58f87f25168b6d9bd3af41a1ce3b1bc1a34384f1db2b4d575bc88535c03dcf3b461cd9765ea1d4b1ef81db601dd9b48c422618b6d2dfd471ea05f6d477ce8c89defbe9037d0ede9c2c40689b328ce2b645fcbb32d120a5715c2a0f6553bf7925f321e6b30ccd49",
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
