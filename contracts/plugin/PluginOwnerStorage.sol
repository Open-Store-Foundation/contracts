// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @dev Storage structure for plugin ownership data
 * @param owner The address of the current owner
 */
struct OwnerData {
    address owner;
}

/**
 * @title PluginOwnerStorage
 * @dev Library for managing plugin ownership storage using diamond storage pattern
 * @notice Provides isolated storage for ownership data that doesn't conflict with plugin storage
 */
library PluginOwnerStorage {

    bytes32 internal constant OWNER_KEEPER = keccak256("openstore.plugin.storage.OwnerKeeper");

    /**
     * @dev Returns storage reference for plugin ownership data
     * @return ds Storage reference to the ownership data
     */
    function ownerData() internal pure returns (OwnerData storage ds) {
        bytes32 storagePosition = OWNER_KEEPER;
        assembly {
            ds.slot := storagePosition
        }
        return ds;
    }
}

