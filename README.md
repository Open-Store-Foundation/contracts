## OpenStore Smart Contracts

> **⚠️ ALPHA**: This is an ALPHA release. Deployed addresses will change for the upcoming BETA. The on-chain API will be finalized by BETA; future updates will avoid breaking changes by introducing new plugin versions only.

An on-chain plugin-driven store for publishing and distributing application builds.

### Networks

- **BSC Testnet** (chainId 97)
  - RPC: `https://bsc-testnet.publicnode.com`

### Deployed Addresses (BSC Testnet)

| Contract | Address |
| --- | --- |
| ContractStorage | `0x76e55C2791AdB0c6a2CD5b8317b188608325961E` |
| ContractsFactory | `0xE994189222edE5fF9056aa00BB70a1eeF42880C7` |
| AssetlinksOracle | `0x0F61D8D6c9D6886ac7cba72716E1b98C4379E0f7` |
| OpenStoreRequestHandlerV1 | `0x43e8A87e6fB8e9BbF2aB4121F40E9781A1489831` |
| OpenStore | `0x6Edac88EA58168a47ab61836bCbAD0Ac844498A6` |
| AppOwnerPluginV1 | `0x77F67523F8b0e7D4519B91344F629c2180447B0f` |
| AppBuildsPluginV1 | `0x0F09669588952cA48368dd8361662D549CcCE987` |
| AppDistributionPluginV1 | `0x51C3A4282FB9F00705Be26f11cB7EE4Cc20274C4` |
| PublisherAccountAppsPluginV1 | `0x48A93cF38ac4cE6FE16f2E8b8a9a7B24b46445A8` |
| PublisherGreenfieldPluginV1 | `0x06cF16521A903971FF8F2635931dA3768e294350` |

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
BSC_TEST_DEPLOY_PK=
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

- `bsctest` uses chainId 97 and reads `BSC_TEST_DEPLOY_PK` and `DEPLOY_PK` from the environment.

### ABIs and Typechain

- ABIs are exported to `reports/abi` after running `yarn abi`.
- Typechain types are generated under `typechain-types` during compile.

### License

See `LICENSE`.
