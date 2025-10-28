// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

struct PubRequest {
    // 1 - android_build
    uint256 reqType;
    // app/game/book etc
    address target;
    // android_build - (int64, uint64, uint8) - (versionCode, ownerVersion, trackId)
    bytes data;
}

/**
 * @dev Main state structure for the OpenStore consensus system
 * Contains all validator, request, proposal, voting, and block data
 */
struct OpenStoreStateV0 {
    // Requests
    uint256 nextRequestIdToCreate;             // Next request ID to be assigned
}

//////////////////
//////////////////
//////////////////

/**
 * @dev Storage for validated builds and release tracks
 */
struct OpenStoreVaultV0 {
    mapping(address => bool) visibility; // app -> is_visible

    mapping(address => mapping(uint256 => uint256)) builds; // app -> versionCode -> ownerVersion TODO check
    mapping(address => mapping(uint256 => uint256)) tracks; // app -> trackId -> versionCode
}

//////////////////
//////////////////
//////////////////

/**
 * @dev Configuration parameters for the OpenStore system
 */
struct OpenStoreConfigV0 {
    // Main
    bool isRequestsSuspended;           // Flag to suspend new validation requests

    address oracle;                     // Address of the assetlinks oracle
    address requestHandler;             // Address of the request handler contract
}

//////////////////
//////////////////
//////////////////

/**
 * @title OpenStoreStorage
 * @dev Library for managing OpenStore storage using diamond storage pattern
 * @notice Provides isolated storage for different components of the system
 */
library OpenStoreStorageV0 {
    bytes32 private constant OPENSTORE_STORAGE_POSITION = keccak256("openstore.state.v0");

    /**
     * @dev Returns storage reference for the main OpenStore state
     * @return state Storage reference to the consensus system state
     */
    function openStoreState() internal pure returns (OpenStoreStateV0 storage state) {
        bytes32 position = OPENSTORE_STORAGE_POSITION;
        assembly {
            state.slot := position
        }
        return state;
    }

    bytes32 private constant OPENSTORE_VAULT_POSITION = keccak256("openstore.vault.v0");

    /**
     * @dev Returns storage reference for the validated builds vault
     * @return state Storage reference to the vault containing validated builds
     */
    function openStoreVault() internal pure returns (OpenStoreVaultV0 storage state) {
        bytes32 position = OPENSTORE_VAULT_POSITION;
        assembly {
            state.slot := position
        }
        return state;
    }

    bytes32 private constant OPENSTORE_CONFIG_POSITION = keccak256("openstore.config.v0");

    /**
     * @dev Returns storage reference for the system configuration
     * @return state Storage reference to the configuration parameters
     */
    function openStoreConfig() internal pure returns (OpenStoreConfigV0 storage state) {
        bytes32 position = OPENSTORE_CONFIG_POSITION;
        assembly {
            state.slot := position
        }
        return state;
    }

    /**
    * @dev Updates the store configuration with validation
     * @param to The storage configuration to update
     * @param from The new configuration values to apply
     * @notice Validates configuration parameters and applies updates
     */
    function setStoreConfig(OpenStoreConfigV0 storage to, OpenStoreConfigV0 memory from) internal {
        // * Use setIsQueueSuspended and setIsQueueSuspended
        // to.isRequestsSuspended = from.isRequestsSuspended;
        // to.isQueueSuspended = from.isQueueSuspended;

        // Main
        to.oracle = from.oracle;
        to.requestHandler = from.requestHandler;
    }
}
