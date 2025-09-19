// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @dev Storage structure for publisher account data
 * @param name The name of the publisher account
 */
struct PublisherAccountStorageData {
    string name;
}

/**
 * @title PublisherFacetStorageV1
 * @dev Library for managing publisher account storage using diamond storage pattern
 * @notice Provides access to publisher account data storage
 */
library PublisherFacetStorageV1 {

    bytes32 internal constant DEV_CONTRACTS_APPS_V1 = keccak256("openstore.diamond.storage.PublisherFacetStorage.v1");

    /**
     * @dev Returns storage reference for publisher account data
     * @return ds Storage reference to the publisher account data
     */
    function common() internal pure returns (PublisherAccountStorageData storage ds) {
        bytes32 storagePosition = DEV_CONTRACTS_APPS_V1;
        assembly {
            ds.slot := storagePosition
        }
        return ds;
    }
}
