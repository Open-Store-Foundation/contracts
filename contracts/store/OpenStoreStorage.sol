// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @dev Represents a block proposal or finalized block in the consensus system
 * @param id The unique block identifier
 * @param fromRequestId Starting request ID for this block (inclusive)
 * @param toRequestId Ending request ID for this block (exclusive)
 * @param result Bitmask representing the validation results for each request
 * @param objectId The serialized block data
 * @param objectHash Hash of the block content for integrity verification
 * @param protocolId The protocol version used for this block
 * @param blockMask Additional flags (bit 0: is discussion block)
 * @param createdBy The validator who created this block
 */
struct BlockRef {
    uint256 id;

    uint256 fromRequestId;
    uint256 toRequestId; // to exclusive
    uint256 result; // bitset of results

    bytes objectId;
    bytes32 objectHash;
    uint16 protocolId;

    uint8 blockMask; // 00000001 - is discussion
    address createdBy;
}

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
 * @param balance Available balance for proposals and operations
 * @param totalBalance Total staked balance including locked amounts
 */
struct Validator {
    uint256 id;
    uint256 version;
    uint256 blocksCreated;
    uint256 votingBalance;
    uint256 balance;
    uint256 totalBalance;
    uint256 lastActivityBlockId; // Internal block id of last validator activity
}

/**
 * @dev Main state structure for the OpenStore consensus system
 * Contains all validator, request, proposal, voting, and block data
 */
struct OpenStoreState {
    // Validators
    uint256 totalBalance;              // Total staked balance across all validators
    uint256 contractBalance;           // Contract's internal balance
    uint256 nextBlockId;               // Next block ID to be assigned
    address[] activeValidators;        // Array of registered validator addresses
    mapping(address => Validator) validators;           // validator address -> validator data
    mapping(uint256 => address) queue;                  // blockId -> assigned validator
    mapping(address => uint256) validatorLocker;        // validator -> assigned blockId
    mapping(address => uint256) emergencyLocker;        // validator -> emergency blockId

    // Requests
    uint256 nextRequestId;             // Next request ID to be assigned
    uint256 nextFinalRequestId;        // Next request ID to be finalized
    mapping(uint256 => RequestInfo) requests;           // requestId -> request data

    // Proposal
    uint256 nextProposalBlockId;       // Next block ID that can be proposed
    uint256 nextProposalTimestampFrom; // Timestamp when proposals can start
    uint256 proposalsOnVoting;         // Number of proposals currently being voted on
    mapping(uint256 => uint256) proposalVotingCreatedAt; // blockId -> voting start timestamp

    mapping(uint256 => address[]) blockProposers;                    // blockId -> array of proposers
    mapping(uint256 => mapping(bytes32 => bool)) blockProposalsHashes; // blockId -> hash -> exists
    mapping(uint256 => mapping(address => BlockRef)) blockProposals;    // blockId -> proposer -> block

    // Voting
    mapping(uint256 => mapping(address => address[])) blockVoters;  // blockId -> proposer -> voters
    mapping(uint256 => mapping(address => address)) votes;          // blockId -> voter -> voted proposer
    mapping(uint256 => mapping(address => uint128)) masks;          // blockId -> voter -> unavailability mask

    // Blocks
    uint256 nextFinalBlockId;          // Next block ID to be finalized
    mapping(uint256 => BlockRef) blocks; // blockId -> finalized block data
}

//////////////////
//////////////////
//////////////////

/**
 * @dev Storage for validated builds and release tracks
 */
struct OpenStoreVault {
    mapping(address => mapping(uint256 => uint256)) builds;     // app -> buildId -> ownerVersion
    mapping(address => mapping(uint256 => uint256)) tracks;     // app -> trackId -> latest buildId
                                                                // Track IDs: 1=release, 2=open-beta, 3=alpha, custom=4+
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
    uint64 version;                     // Protocol version
    uint64 minValidatorVersion;         // Minimum required validator version
    bool isRequestsSuspended;           // Flag to suspend new validation requests
    bool isQueueSuspended;              // Flag to suspend validator queue operations

    address oracle;                     // Address of the assetlinks oracle
    address requestHandler;             // Address of the request handler contract

    // Limits
    uint8 maxParallelProposals;         // Maximum number of parallel proposals allowed
    uint256 maxReqPerBlock;             // Maximum requests allowed per block
    uint256 maxInactiveBlocks;          // Maximum inactive blocks before penalties

    // Economic Parameters
    uint256 validationRequestAmount;    // Fee for request validation
    uint256 baseProposalAmount;         // Base stake required for proposals
    uint256 baseVoteAmount;             // Base cost for voting
    uint256 overdueProposalFee;         // Penalty for overdue proposals
    uint256 inactiveFee;                // Penalty for inactivity
    uint256 minStakeAmount;             // Minimum stake to become validator
    uint256 basicAmount;          // Amount that must remain locked

    // Time Windows
    uint256 proposalBlockWindow;        // Time window for primary proposer exclusivity
    uint256 voteBlockWindow;            // Time window for voting on proposals
    uint256 minFinalizationWindow;      // Minimum wait time between block finalizations
}

//////////////////
//////////////////
//////////////////

/**
 * @title OpenStoreStorage
 * @dev Library for managing OpenStore storage using diamond storage pattern
 * @notice Provides isolated storage for different components of the system
 */
library OpenStoreStorage {
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
        to.requestHandler = from.requestHandler;

        require(to.version < from.version, "1");
        to.version = from.version;

        to.minValidatorVersion = from.minValidatorVersion;

        // Limits
        to.maxParallelProposals = from.maxParallelProposals;
        require(from.maxReqPerBlock <= 128, "maxReqPerBlock can't be more than 128");
        to.maxReqPerBlock = from.maxReqPerBlock;
        to.maxInactiveBlocks = from.maxInactiveBlocks;

        // Amounts
        to.validationRequestAmount = from.validationRequestAmount;
        to.baseProposalAmount = from.baseProposalAmount;
        to.baseVoteAmount = from.baseVoteAmount;
        require(from.overdueProposalFee < from.baseProposalAmount, "overdueProposalFee should be less than baseProposalAmount");
        to.overdueProposalFee = from.overdueProposalFee;
        to.inactiveFee = from.inactiveFee;

        uint256 basicAmount = from.baseVoteAmount * from.maxParallelProposals; // maxParallel * vote
        to.basicAmount = basicAmount;
        require(
            basicAmount + from.baseProposalAmount <= from.minStakeAmount,
            "basicAmount+proposalAmount should be less or equal to minStakeAmount"
        );
        to.minStakeAmount = from.minStakeAmount;

        // Duration
        to.proposalBlockWindow = from.proposalBlockWindow;
        to.voteBlockWindow = from.voteBlockWindow;

        require(from.minFinalizationWindow < from.voteBlockWindow, "4");
        to.minFinalizationWindow = from.minFinalizationWindow;
    }
}
