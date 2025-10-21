// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;


/**
 * @dev Represents a validation request in the system
 * @param reqType The type of request (1 = android_build, etc.)
 * @param target The contract address being validated (app/game/book etc.)
 * @param data Encoded request data (for android_build: versionCode, ownerVersion, trackId)
 */
struct RequestInfo {
    // 1 - android_build
    uint256 reqType;
    // app/game/book etc
    address target;
    // android_build - (int64, uint64, uint8) - (versionCode, ownerVersion, trackId)
    bytes data;
}

/**
 * @dev Represents a validator in the consensus system
 * @param id The validator's position in the activeValidators array (0 = not registered)
 * @param version The validator's software version
 * @param blocksCreated Number of blocks this validator has successfully created
 * @param votingBalance Available balance for voting operations
 * @param totalBalance Total staked balance including locked amounts
 */
struct Validator {
    uint256 version;

    uint256 validatedRequests;

    uint256 balanceAndPower;
    int256 withdrawStatus;

    uint256 nextRequestIdToVote;
    uint256 nextRequestIdToClaim;
}

/**
 * @dev Main state structure for the OpenStore consensus system
 * Contains all validator, request, proposal, voting, and block data
 */
struct OpenStoreState {
    // Validators
    uint256 totalBalance;
    mapping(address => Validator) validators;           // validator address -> validator data

    // Requests
    uint256 nextRequestIdToCreate;             // Next request ID to be assigned
    uint256 nextRequestIdToVote;               // Next request ID to be finalized

    mapping(uint256 => RequestInfo) requests;           // requestId -> request data
    mapping(uint256 => uint256) requestVotingDeadline;  // requestId -> voting deadline timestamp

    mapping(uint256 => mapping(uint8 => uint256)) votingState; // reqId - status - uint256(uint128(balance) and uint128(power))
    mapping(uint256 => mapping(address => uint256)) votes; // reqId - validator - uint256(uint128(balance) and uint120(power) and uint8(status))
    mapping(uint256 => uint8) statusWinner;
}

//////////////////
//////////////////
//////////////////

/**
 * @dev Storage for validated builds and release tracks
 */
struct OpenStoreVault {
    mapping(address => bool) visibility;                        // app -> is_visible
}

//////////////////
//////////////////
//////////////////

/**
 * @dev Configuration parameters for the OpenStore system
 */
struct OpenStoreConfig {
    // Main
    bool isRequestsSuspended;           // Flag to suspend new validation requests
    bool isVoteSuspended;              // Flag to suspend validator queue operations

    uint64 minValidatorVersion;         // Minimum required validator version
    address oracle;

    // Economic Parameters
    uint256 validationRequestAmount;    // Fee for request validation
    uint256 minStakeAmount;             // Minimum stake to become validator
}

//////////////////
//////////////////
//////////////////

/**
 * @title OpenStoreStorage
 * @dev Library for managing OpenStore storage using diamond storage pattern
 * @notice Provides isolated storage for different components of the system
 */
library OpenStoreStorageV2 {
    bytes32 private constant OPENSTORE_STORAGE_POSITION = keccak256("openstore.state.v1");

    /**
     * @dev Returns storage reference for the main OpenStore state
     * @return state Storage reference to the consensus system state
     */
    function openStoreState() internal pure returns (OpenStoreState storage state) {
        bytes32 position = OPENSTORE_STORAGE_POSITION;
        assembly {
            state.slot := position
        }
        return state;
    }

    bytes32 private constant OPENSTORE_VAULT_POSITION = keccak256("openstore.vault.v1");

    /**
     * @dev Returns storage reference for the validated builds vault
     * @return state Storage reference to the vault containing validated builds
     */
    function openStoreVault() internal pure returns (OpenStoreVault storage state) {
        bytes32 position = OPENSTORE_VAULT_POSITION;
        assembly {
            state.slot := position
        }
        return state;
    }

    bytes32 private constant OPENSTORE_CONFIG_POSITION = keccak256("openstore.config.v1");

    /**
     * @dev Returns storage reference for the system configuration
     * @return state Storage reference to the configuration parameters
     */
    function openStoreConfig() internal pure returns (OpenStoreConfig storage state) {
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
    function setStoreConfig(OpenStoreConfig storage to, OpenStoreConfig memory from) internal {
        // * Use setIsQueueSuspended and setIsQueueSuspended
        // to.isRequestsSuspended = from.isRequestsSuspended;
        // to.isQueueSuspended = from.isQueueSuspended;

        // Main
        to.oracle = from.oracle;
        to.minValidatorVersion = from.minValidatorVersion;

        // Amounts
        to.validationRequestAmount = from.validationRequestAmount;
        to.minStakeAmount = from.minStakeAmount;
    }
}
