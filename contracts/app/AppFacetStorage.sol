// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @dev General information structure for an application
 * @param id Unique identifier for the application (package name)
 * @param name Display name of the application
 * @param description Description of the application
 * @param protocolId The protocol identifier
 * @param categoryId The category identifier for this app
 * @param platformId The platform identifier
 */
struct AppGeneralInfo {
    string id;
    string name;
    bytes description; // base64

    uint16 protocolId;
    uint16 categoryId;
    uint16 platformId;
}

/**
 * @title AppFacetStorage
 * @dev Library for managing application general information storage
 * @notice Provides access to app metadata storage using diamond storage pattern
 */
library AppFacetStorage {

    bytes32 internal constant APP_STORAGE_V1 = keccak256("openstore.storage.AppFacetStorage.v1");

    /**
     * @dev Returns storage reference for general app information
     * @return ds Storage reference to the app general information
     */
    function general() internal pure returns (AppGeneralInfo storage ds) {
        bytes32 storagePosition = APP_STORAGE_V1;
        assembly {
            ds.slot := storagePosition
        }
        return ds;
    }
}
