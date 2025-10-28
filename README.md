## OpenStore Smart Contracts

> **⚠️ ALPHA**: This is an ALPHA release. Deployed addresses will change for the upcoming BETA. The on-chain API will be finalized by BETA; future updates will avoid breaking changes by introducing new plugin versions only.

An on-chain plugin-driven store for publishing and distributing application builds.

### Networks

- **BSC Testnet** (chainId 97)
  - RPC: `https://bsc-testnet.publicnode.com`

### Deployed Addresses (BSC Testnet)

| Contract                     | Address |
|------------------------------| --- |
| Multicall                    | `0x3f7AdDD276bC5c1a2Fffb329DD718f1fa0625D84` |
| ContractStorage              | `0x66E4Ae87d237A7630CF1acf9EA32E027bF2096c2` |
| PublisherAccountFactory      | `0x7bf2b3901E3198268ec071F43A08dBD365017354` |
| AssetlinksOracle             | `0xCA21F6ab7D9Cf14444028394016066778Cbe1B4B` |
| OpenStoreRequestHandlerV0    | `0x5f56DccEfe191f1FBf1ca12600D71D1aCABf1298` |
| OpenStoreV0                  | `0x4dc802c0E64Eb0C9d9b278F70b6a7d6e21908a46` |
| AppOwnerPluginV1             | `0xD2dfb8a2D0f2b90f3F912566F4c4Fb0a3e9Bc336` |
| AppBuildsPluginV1            | `0xe00e09e2028046DE01C9aEc7C683cF0ce08016B1` |
| AppDistributionPluginV1      | `0x76F7A70d7eCf4483Fa08D10511F997c97b247737` |
| PublisherAccountAppsPluginV1 | `0x374DA7507CB00FAEc54fa4226eF6c45eC99bA2E4` |
| PublisherGreenfieldPluginV1  | `0xaE3f8bD0a3112aE5860a72DE494A238997210756` |

### Prerequisites

- Node.js 18+
- Yarn 1.x

### Install

```bash
yarn install
```

### Environment

Create a `.env` file in the project root.

```bash
DEPLOY_PK=
DEPLOY_ADDRESS=
TEST_PK=
TEST_ADDRESS=
BSCSCAN_API=
# Optional for gas report
REPORT_GAS=true
CMC_API=
# Optional for ABI export
CONTRACT_TS_DIRS=
CONTRACTS_JSON_DIRS=
# Required for graph.ts
PUBLISHER_FACTORY=
```

### ⚠️ Multicall address (required)

For simplicity the multicall address is hardcoded. Update it to match your deployment:

- In `contracts/multicall/Trustable.sol`, change `address private constant MULTICALL = 0x3f7AdDD276bC5c1a2Fffb329DD718f1fa0625D84;` to your `TrustedMulticall` address.
- In `test/utils/multicall.ts`, change `EXPECTED_MULTICALL_PROD_ADDRESS` and `EXPECTED_MULTICAST_TEST_ADDRESS` to your addresses.

> ❗️ Important: If these are not updated, authorization checks will fail and calls restricted by `onlyMulticall` will revert.

### Useful Scripts

- **Local Hardhat node**

```bash
yarn lh
```

- **Compile contracts**

```bash
yarn compile
```

- **Run tests**

```bash
yarn test:main
yarn test:lh
```

- **Coverage and size reports**

```bash
yarn coverage
yarn size
```

- **Generate ABIs**

Exports contract ABIs based on directories specified in environment variables:
- `CONTRACT_TS_DIRS`: colon-separated directories to export ABIs as TypeScript modules
- `CONTRACTS_JSON_DIRS`: colon-separated directories to export ABIs as JSON files

```bash
yarn abi
```

- **Insert SPDX licenses into all .sol files**

```bash
yarn license:spdx
```

- **Deploy**

Requires `DEPLOY_PK` and `DEPLOY_ADDRESS`. Optionally set `BSCSCAN_API` to enable source verification.

```bash
yarn deploy:lh
yarn deploy:bsctest
yarn deploy:bsc
```

- **Verify on BscScan**

Requires `BSCSCAN_API`.

```bash
yarn verify:lh
yarn verify:bsctest
yarn verify:bsc
```

- **Developer tools**

```bash
yarn dev:lh
yarn dev:bsctest
```

- **Interact via CLI**

Requires `TEST_PK` and `TEST_ADDRESS`.

```bash
yarn cli:lh
yarn cli:bsctest
```

### Tools Overview

- **abi.ts**: export ABIs
  - `CONTRACT_TS_DIRS`: directories split by `:` for TS outputs
  - `CONTRACTS_JSON_DIRS`: directories split by `:` for JSON outputs
- **spdx.ts**: insert licenses into all `.sol` files
- **manager.ts**: helpers to interact with contracts
- **dev.ts**: internal tool to interact/test contracts
- **deployer.ts**: helper class to deploy contracts in local or any env
- **deploy.ts**: deploy contracts to Testnet/Mainnet
  - `DEPLOY_PK`: deploy PK URL
  - `DEPLOY_ADDRESS`: should be retrieved from `DEPLOY_PK` for safety
  - `BSCSCAN_API`: set to enable contract verification (upload sources)
- **defaults.ts**: default data for testing
- **cli.ts**: localhost/testnet deploy tool; uses `TEST_PK` and `TEST_ADDRESS`


### Hardhat Networks

Hardhat network configuration is defined in `hardhat.config.ts`.

- `bsctest` uses chainId 97 and reads `DEPLOY_PK` from the environment.

### ABIs and Typechain

- ABIs are exported to `reports/abi` after running `yarn abi`.
- Typechain types are generated under `typechain-types` during compile.

### License

See `LICENSE`.
