# Licensing

This project uses the Apache License 2.0. 

## Structure

- **SPDX Identifiers**: Each Solidity contract file (`.sol`) contains only the SPDX license identifier at the top:
  ```solidity
  // SPDX-License-Identifier: Apache-2.0
  ```

- **Full License Text**: The complete Apache 2.0 license text is available in the [`LICENSE`](./LICENSE) file in the project root.

## Adding Licenses to New Contract Files

To add Apache 2.0 SPDX identifiers to new contract files, use the provided script:

```bash
yarn license:add-spdx
```

This script will:
- ✅ Find all `.sol` files in the `contracts/` directory
- ✅ Add `// SPDX-License-Identifier: Apache-2.0` to files without any license
- ✅ Update existing SPDX identifiers to use Apache-2.0
- ✅ Skip files that already have the correct license
- ✅ Preserve existing code structure and formatting

## Manual Addition

For new contract files, simply add this line at the very top of the file:

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

// Your contract code here...
```

## Files Covered

The licensing applies to all Solidity contract files in:
- `contracts/app/`
- `contracts/common/`
- `contracts/dev/`
- `contracts/interfaces/`
- `contracts/libs/`
- `contracts/multicall/`
- `contracts/oracle/`
- `contracts/plugin/`
- `contracts/store/`

All 30 contract files are properly licensed with Apache 2.0 SPDX identifiers.