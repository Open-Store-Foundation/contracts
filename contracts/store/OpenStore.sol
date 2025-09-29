// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "./OpenStoreStorage.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {BitmaskComparator} from "../libs/BitmaskComparator.sol";
import {BytesParser} from "../libs/BytesParser.sol";
import {IOpenStoreRequestHandler} from "./IOpenStoreRequestHandler.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OpenStoreConfig, OpenStoreState, OpenStoreStorage, OpenStoreVault, Validator, BlockRef, RequestInfo} from "./OpenStoreStorage.sol";
import {PluginManager} from "../plugin/PluginManager.sol";
import {PluginOwnable} from "../plugin/PluginOwnable.sol";
import {Trustable} from "../multicall/Trustable.sol";
import {VersionableOwner} from "../interfaces/VersionableOwner.sol";

/**
 * @title OpenStore
 * @notice A decentralized application store built on a consensus-based validation system
 * @dev This contract implements a blockchain-based app store where validators stake tokens to participate
 *      in validating app submissions, distributions, and metadata. The system uses a democratic voting
 *      mechanism to achieve consensus on proposed blocks of validated requests.
 * 
 * Key Features:
 * - Validator registration with staking requirements
 * - Block proposal and voting system for request validation
 * - Economic incentives through rewards and slashing
 * - Request queuing and processing system
 * - Asset tracking and distribution channels
 * - Plugin-based architecture for extensibility
 * 
 * The workflow involves:
 * 1. Validators register by staking minimum required amount
 * 2. Users submit validation requests (app submissions, updates, etc.)
 * 3. Validators propose blocks containing batches of requests with validation results
 * 4. Other validators vote on proposals during a specified time window
 * 5. Winning proposals are finalized, and rewards/slashing are distributed
 */
contract OpenStore is PluginManager {

    using BytesParser for bytes;
    using BitmaskComparator for uint256;

    /// @notice Custom error with error code for all OpenStore failures
    error OpenStoreError(uint16 code);
    
    // Error codes
    uint16 private constant ERROR_VERSION_CONFIG_MUST_INCREASE = 1;           // Version must be higher than current
    uint16 private constant ERROR_VALIDATOR_UNSUPPORTED_VERSION = 2;          // Validator version too old
    uint16 private constant ERROR_VALIDATOR_ALREADY_REGISTERED = 3;           // Validator already exists
    uint16 private constant ERROR_INSUFFICIENT_STAKE = 4;                     // Not enough stake to register/maintain
    uint16 private constant ERROR_VALIDATOR_NOT_REGISTERED = 5;               // Validator doesn't exist
    uint16 private constant ERROR_VALIDATOR_IN_QUEUE = 6;                     // Validator has assigned block
    uint16 private constant ERROR_VALIDATOR_IN_EMERGENCY_LOCK = 7;            // Validator in emergency lock
    uint16 private constant ERROR_QUEUE_SUSPENDED = 8;                        // Queue operations suspended
    uint16 private constant ERROR_VALIDATOR_ALREADY_IN_QUEUE = 9;             // Validator already has block assigned
    uint16 private constant ERROR_BLOCK_ID_NOT_INCREMENTAL = 10;              // Block IDs must be sequential
    uint16 private constant ERROR_INSUFFICIENT_BALANCE_FOR_PROPOSAL = 11;     // Not enough balance to propose
    uint16 private constant ERROR_INSUFFICIENT_VOTING_BALANCE = 12;           // Not enough voting balance
    uint16 private constant ERROR_CANNOT_UNASSIGN_BLOCK = 13;                 // Block can't be unassigned
    uint16 private constant ERROR_INSUFFICIENT_BALANCE = 14;                  // General insufficient balance
    uint16 private constant ERROR_NOT_TARGET_OWNER = 17;                      // Caller not owner of target
    uint16 private constant ERROR_BLOCK_ID_NOT_NEXT_TO_FINALIZE = 20;         // Block not ready for finalization
    uint16 private constant ERROR_INVALID_REQUEST_ID_RANGE = 21;              // Invalid request ID range
    uint16 private constant ERROR_TOO_MANY_REQUESTS_IN_BLOCK = 22;            // Exceeds max requests per block
    uint16 private constant ERROR_SENDER_NOT_BLOCK_OWNER = 23;                // Sender doesn't own the block
    uint16 private constant ERROR_INVALID_TO_REQUEST_ID = 24;                 // Invalid ending request ID
    uint16 private constant ERROR_INVALID_FROM_REQUEST_ID = 25;               // Invalid starting request ID
    uint16 private constant ERROR_PROPOSAL_VALIDATOR_ALREADY_EXISTS = 26;     // Validator already has proposal
    uint16 private constant ERROR_PROPOSAL_HASH_ALREADY_EXISTS = 26;          // Duplicate proposal hash
    uint16 private constant ERROR_NO_PROPOSAL_TO_DISCUSS = 27;                // No proposal exists for discussion
    uint16 private constant ERROR_DISCUSSION_FROM_REQ_ID_MISMATCH = 28;       // Discussion request ID mismatch
    uint16 private constant ERROR_DISCUSSION_TO_REQ_ID_MISMATCH = 29;         // Discussion request ID mismatch
    uint16 private constant ERROR_DISCUSSION_RESULT_SAME = 43;                // Discussion has same result
    uint16 private constant ERROR_CANNOT_DISCUSS_AFTER_VOTE = 30;             // Can't discuss after voting
    uint16 private constant ERROR_MAX_PARALLEL_PROPOSALS_REACHED = 31;        // Too many parallel proposals
    uint16 private constant ERROR_BLOCK_ID_NOT_NEXT_TO_PROPOSE = 32;          // Block not next in sequence
    uint16 private constant ERROR_VOTER_NOT_REGISTERED = 33;                  // Voter not registered
    uint16 private constant ERROR_CANNOT_VOTE_FOR_SELF = 34;                  // Self-voting prohibited
    uint16 private constant ERROR_PROPOSAL_NOT_FOUND = 35;                    // Proposal doesn't exist
    uint16 private constant ERROR_VOTING_PERIOD_CLOSED = 36;                  // Voting window expired
    uint16 private constant ERROR_INSUFFICIENT_BALANCE_FOR_VOTE = 37;         // Not enough balance to vote
    uint16 private constant ERROR_ALREADY_VOTED = 38;                         // Already voted on this proposal
    uint16 private constant ERROR_PROPOSAL_NOT_READY_TO_FINALIZE = 39;        // Proposal can't be finalized yet
    uint16 private constant ERROR_INVALID_TRACK_ID = 40;                      // Invalid distribution track ID
    uint16 private constant ERROR_BUILD_VERSION_DOWNGRADED = 41;              // Version lower than current
    uint16 private constant ERROR_VALIDATOR_STILL_ACTIVE = 44;                // Validator still active

    /// @dev Status codes for validation results
    uint256 constant public STATUS_UNAVAILABLE = 0;  // Request could not be processed
    uint256 constant public STATUS_SUCCESS = 1;      // Validation successful
    uint256 constant public STATUS_RESERVED = 2;     // Reserved for future use
    uint256 constant public STATUS_ERROR = 3;        // Validation failed with error

    // Constants
    /// @dev Precision scale for voting calculations and vote unit (1 gwei)
    uint256 private constant PRECISION_SCALE_AND_VOTE_UNIT = 1 gwei;
    /// @dev Maximum number of requests allowed in a single block
    uint256 private constant MAX_REQ_IN_BLOCK = 128;

    // Block masks
    /// @dev Bitmask to identify discussion blocks (alternative proposals)
    uint8 private constant BI_MASK_IS_DISCUSSION = 1 << 0;

    // Events
    /// @notice Emitted when configuration is updated
    event ConfigChanged();
    
    /// @notice Emitted when queue suspension status changes
    /// @param isSuspended True if queue is suspended
    event QueueStatusChanged(bool isSuspended);
    
    /// @notice Emitted when request submission status changes
    /// @param isSuspended True if requests are suspended
    event RequestsStatusChanged(bool isSuspended);

    /// @notice Emitted when a new validation request is submitted
    /// @param target The target contract address
    /// @param requestId The unique request identifier
    /// @param reqType The type of request
    /// @param data The request data
    event NewRequest(address indexed target, uint256 requestId, uint256 reqType, bytes data);
    
    /// @notice Emitted when a validator is assigned to a block
    /// @param blockId The block identifier
    /// @param validator The validator address
    event QueueChanged(uint256 blockId, address validator);
    
    /// @notice Emitted when a block proposal is created
    /// @param blockId The block identifier
    /// @param validator The proposing validator
    /// @param fromRequestId Starting request ID in the block
    /// @param toRequestId Ending request ID in the block
    /// @param isDiscussion True if this is a discussion/alternative proposal
    event BlockProposed(uint256 blockId, address validator, uint256 fromRequestId, uint256 toRequestId, bool isDiscussion);
    
    /// @notice Emitted when a validator votes on a proposal
    /// @param blockId The block identifier
    /// @param validator The validator being voted for
    /// @param voter The address casting the vote
    event ValidatorVoted(uint256 blockId, address validator, address voter);
    
    /// @notice Emitted when a block is finalized
    /// @param blockId The block identifier
    /// @param creator The winning validator
    /// @param objectId The finalized object identifier
    event BlockFinalized(uint256 blockId, address creator, bytes objectId);
    
    /// @notice Emitted when a build is added to a distribution track
    /// @param target The target asset address
    /// @param trackId The distribution track identifier
    /// @param versionCode The version code
    event AddedToTrack(address indexed target, uint256 trackId, uint256 versionCode);
    
    /// @notice Emitted when a validator is force unregistered due to inactivity
    /// @param validator The unregistered validator
    /// @param sender The address that triggered the unregistration
    /// @param reward The reward paid to the sender
    event ValidatorForceUnregistered(address indexed validator, address indexed sender, uint256 reward);

    /// @notice Possible statuses when checking if a validator can be assigned to a block
    enum ValidatorAssignStatus {
        Assignable,          // Can be assigned to next block
        VersionOutdated,     // Validator version too old
        NotRegistered,       // Validator not registered
        NotEnoughVotes,      // Insufficient voting balance
        AlreadyAssigned      // Already has block assigned
    }

    /**
     * @notice Initializes the OpenStore contract with configuration
     * @param _owner The owner address who can manage the contract
     * @param _config The initial configuration parameters
     * @dev Sets up initial state with block and request IDs starting at 1,
     *      and adds a placeholder at index 0 for active validators array
     */
    constructor(
        address _owner,
        OpenStoreConfig memory _config
    ) PluginManager(_owner) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();

        // Initialize block tracking - start at 1 to avoid confusion with 0/null values
        state.nextBlockId = 1;
        state.nextProposalBlockId = 1;
        state.nextFinalBlockId = 1;

        // Initialize request tracking
        state.nextRequestId = 1;
        state.nextFinalRequestId = 1;

        // Add placeholder at index 0 for validators array (0 means unregistered)
        state.activeValidators.push(address(0));

        // Set initial configuration
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        OpenStoreStorage.setStoreConfig(config, _config);
    }

    //////////////////////
    // Configuration Management
    //////////////////////

    /**
     * @notice Gets the current protocol version
     * @return The current version number
     */
    function version() external view returns (uint64) {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        return config.version;
    }

    /**
     * @notice Updates the protocol version (owner only)
     * @param newVersion The new version number (must be higher than current)
     * @dev Version can only increase to prevent downgrade attacks
     */
    function setVersion(uint64 newVersion) external onlyOwner {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();

        if (config.version >= newVersion) {
            revert OpenStoreError(ERROR_VERSION_CONFIG_MUST_INCREASE);
        }
        config.version = newVersion;

        emit ConfigChanged();
    }

    /**
     * @notice Gets the minimum required validator version
     * @return The minimum validator version that can participate
     */
    function minValidatorVersion() external view returns (uint64) {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        return config.minValidatorVersion;
    }

    /**
     * @notice Sets the minimum required validator version (owner only)
     * @param newVersion The new minimum validator version
     * @dev Validators below this version cannot participate in validation
     */
    function setMinValidatorVersion(uint64 newVersion) external onlyOwner {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        config.minValidatorVersion = newVersion;

        emit ConfigChanged();
    }

    /**
     * @notice Gets the minimum stake amount required for validator registration
     * @return The minimum stake amount in wei
     */
    function getMinStakeAmount() external view returns (uint256) {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        return config.minStakeAmount;
    }

    function setValidationRequestAmount(uint256 amount) external {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        config.validationRequestAmount = amount;
    }

    function getValidationRequestAmount() external view returns (uint256) {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        return config.validationRequestAmount;
    }

    /**
     * @notice Gets the basic unspendable amount validators must maintain
     * @return The basic amount in wei that cannot be spent
     */
    function getBasicAmount() external view returns (uint256) {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        return config.basicAmount;
    }

    /**
     * @notice Gets the complete current configuration
     * @return The current OpenStoreConfig struct
     */
    function config() external view returns (OpenStoreConfig memory) {
        return OpenStoreStorage.openStoreConfig();
    }

    /**
     * @notice Suspends or resumes request submissions
     * @param isSuspended True to suspend requests, false to resume
     * @dev Can be called by owner or authorized addresses for emergency suspension
     */
    function setIsRequestsSuspended(bool isSuspended) public {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        config.isRequestsSuspended = isSuspended;

        emit RequestsStatusChanged(isSuspended);
    }

    /**
     * @notice Suspends or resumes validator queue operations
     * @param isSuspended True to suspend queue, false to resume
     * @dev Can be called by owner or authorized addresses for emergency suspension
     */
    function setIsQueueSuspended(bool isSuspended) public {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        config.isQueueSuspended = isSuspended;

        emit QueueStatusChanged(isSuspended);
    }

    /**
     * @notice Updates the complete configuration (owner only)
     * @param _config The new configuration to apply
     * @dev Replaces all configuration values with the provided ones
     */
    function updateConfig(OpenStoreConfig calldata _config) external onlyOwner  {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        OpenStoreStorage.setStoreConfig(config, _config);

        emit ConfigChanged();
    }

    /**
     * @notice Placeholder function for saving block data
     * @param blockData The block data to save
     * @return Always returns true
     * @dev Currently not implemented - reserved for future use
     */
    function saveBlockData(bytes calldata blockData) external returns (bool) {
        return true;
    }

    //////////////////////
    // Vault Management - Asset and Build Tracking
    //////////////////////
    
    /**
     * @notice Checks if a build version is verified against the current owner version
     * @param asset The asset contract address
     * @param versionCode The build version to check
     * @return True if the build matches the current owner version
     * @dev Compares stored build ownership version with current asset owner version
     */
    function isBuildVerified(address asset, uint256 versionCode) external view returns (bool) {
        VersionableOwner version = VersionableOwner(asset);
        OpenStoreVault storage vault = OpenStoreStorage.openStoreVault();
        return vault.builds[asset][versionCode] == version.ownerVersion();
    }

    /**
     * @notice Gets the ownership version recorded for a specific build
     * @param asset The asset contract address
     * @param buildId The build identifier
     * @return The ownership version recorded when this build was validated
     * @dev Used to track ownership at the time of build validation
     */
    function getOwnershipVersion(address asset, uint256 buildId) external view returns (uint256) {
        OpenStoreVault storage vault = OpenStoreStorage.openStoreVault();
        return vault.builds[asset][buildId];
    }

    /**
     * @notice Gets the latest version code for an asset on a specific distribution track
     * @param asset The asset contract address
     * @param channel The distribution channel/track identifier
     * @return The latest version code on this track
     * @dev Different tracks can have different versions (e.g., stable, beta, alpha)
     */
    function getLastAppVersion(address asset, uint256 channel) external view returns (uint256) {
        OpenStoreVault storage vault = OpenStoreStorage.openStoreVault();
        return vault.tracks[asset][channel];
    }

    /**
     * @notice Sets the visibility status of an asset in the store
     * @param asset The asset contract address
     * @param isVisible True to make visible, false to hide
     * @dev Controls whether the asset appears in public listings
     */
    function setAssetVisibility(address asset, bool isVisible) external {
        OpenStoreVault storage vault = OpenStoreStorage.openStoreVault();
        vault.visibility[asset] = isVisible;
    }

    //////////////////////
    // State Information
    //////////////////////

    /**
     * @notice Gets the total balance of all registered validators
     * @return The total staked balance across all validators
     * @dev Used for calculating voting power and participation percentages
     */
    function totalBalance() external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.totalBalance;
    }

    /**
     * @notice Gets comprehensive state information for a validator
     * @param validator The validator address to query
     * @return blockNumber Current block number
     * @return nextBlockId Next block ID to be assigned
     * @return nextFinalBlockId Next block ID to be finalized
     * @return emergencyBlockId Block ID where validator is in emergency lock (0 if none)
     * @return nextProposalBlockId Next block ID for proposals
     * @return assignedBlockId Block ID assigned to this validator (0 if none)
     * @return nextRequestToPropose Next request ID that can be proposed
     * @return nextRequestId Next request ID to be assigned
     * @dev Provides a comprehensive state snapshot for validator operations
     */
    function getLastState(address validator) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return (
            block.number,
            state.nextBlockId,
            state.nextFinalBlockId,
            state.emergencyLocker[validator],
            state.nextProposalBlockId,
            state.validatorLocker[validator],
            nextRequestIdToPropose(),
            state.nextRequestId
        );
    }

    //////////////////////
    // Validator Information
    //////////////////////
    
    /**
     * @notice Gets the total balance (stake + earned rewards) of a validator
     * @param validator The validator address
     * @return The validator's total balance including stake and rewards
     */
    function validatorTotalBalance(address validator) external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.validators[validator].totalBalance;
    }

    /**
     * @notice Gets the available balance of a validator
     * @param validator The validator address
     * @return The validator's available balance for operations
     * @dev This is the balance available for proposals, votes, and withdrawals
     */
    function balance(address validator) external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.validators[validator].balance;
    }

    /**
     * @notice Gets the number of blocks successfully validated by a validator
     * @param validator The validator address
     * @return The count of blocks this validator has had finalized
     */
    function blocksValidated(address validator) external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.validators[validator].blocksCreated;
    }

    /**
     * @notice Checks if a validator can be assigned to validate the next block
     * @param validatorAddr The validator address to check
     * @param version The validator's software version
     * @return Status indicating why assignment is possible or not
     * @dev Performs comprehensive eligibility check including version, registration, voting balance, and current assignments
     */
    function validatorAssignStatus(address validatorAddr, uint64 version) view external returns (ValidatorAssignStatus) {
        if (version < this.minValidatorVersion()) {
            return ValidatorAssignStatus.VersionOutdated;
        }

        if (!this.isValidatorRegistered(validatorAddr)) {
            return ValidatorAssignStatus.NotRegistered;
        }

        if (!this.canAssignValidator(validatorAddr)) {
            return ValidatorAssignStatus.NotEnoughVotes;
        }

        if (this.nextBlockIdFor(validatorAddr) > 0) {
            return ValidatorAssignStatus.AlreadyAssigned;
        }

        return ValidatorAssignStatus.Assignable;
    }

    /**
     * @notice Checks if a validator has sufficient voting balance to be assigned a block
     * @param validatorAddr The validator address to check
     * @return True if the validator can be assigned based on voting balance
     * @dev Compares validator's voting balance against required votes based on their stake proportion
     */
    function canAssignValidator(address validatorAddr) view external returns (bool) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        Validator storage validator = state.validators[validatorAddr];
        uint256 votesToEnqueue = votesToAssign(validatorAddr);
        uint256 voteBalance = validator.votingBalance;

        return voteBalance >= votesToEnqueue;
    }

    /**
     * @notice Calculates the number of votes required for a validator to be assigned a block
     * @param validatorAddr The validator address
     * @return The number of votes required based on the validator's stake proportion
     * @dev Validators with larger stakes need more community votes to prevent centralization
     *      Formula: If validator has X% of total stake, they need (X-1)% votes from others
     *      Returns max uint256 if total balance is 0, and 0 if validator share is minimal
     */
    function votesToAssign(address validatorAddr) view private returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        Validator storage validator = state.validators[validatorAddr];
        uint256 validatorTotalBalance = validator.totalBalance;
        uint256 totalBalance = state.totalBalance;

        if (validatorTotalBalance == 0 || totalBalance == 0) {
            return type(uint256).max;
        }

        // Calculate validator's share as percentage in gwei units
        uint256 validatorShareGweiPercent = Math.mulDiv(totalBalance, PRECISION_SCALE_AND_VOTE_UNIT, validatorTotalBalance);
        if (validatorShareGweiPercent <= PRECISION_SCALE_AND_VOTE_UNIT) {
            return 0;
        }

        // Subtract 1 (own vote) from required votes
        // Example: if validator has 10% stake (10 gwei units), they need 9 gwei units of external votes
        uint256 result = validatorShareGweiPercent - PRECISION_SCALE_AND_VOTE_UNIT;
        return result;
    }

    /**
     * @notice Gets all validators who have proposed for a specific block
     * @param blockId The block identifier
     * @return Array of validator addresses who proposed for this block
     * @dev First proposer in array is the main proposer, others are discussions/alternatives
     */
    function getBlockProposers(uint256 blockId) view external returns (address[] memory) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.blockProposers[blockId];
    }

    //////////////////////
    // Block Information
    //////////////////////
    
    /**
     * @notice Gets the next block ID that will be assigned to a validator
     * @return The next block ID in the assignment queue
     * @dev This increments when validators request block assignments
     */
    function nextBlockIdToValidated() external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.nextBlockId;
    }

    /**
     * @notice Gets the block ID assigned to a specific validator
     * @param validator The validator address
     * @return The block ID assigned to this validator (0 if none)
     * @dev Validators can only have one block assigned at a time
     */
    function nextBlockIdFor(address validator) external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.validatorLocker[validator];
    }

    /**
     * @notice Gets the emergency block ID for a validator
     * @param validator The validator address
     * @return The block ID where validator is in emergency lock (0 if none)
     * @dev Emergency lock occurs when validators create discussion proposals or late proposals
     */
    function emergencyBlockIdFor(address validator) external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.emergencyLocker[validator];
    }

    /**
     * @notice Gets the next block ID that can receive proposals
     * @return The next block ID available for proposals
     * @dev This increments when the first proposal is made for a block
     */
    function nextBlockIdToPropose() external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.nextProposalBlockId;
    }

    /**
     * @notice Gets the next block ID that should be finalized
     * @return The next block ID in the finalization queue
     * @dev Blocks must be finalized in order
     */
    function nextBlockIdToFinalize() external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.nextFinalBlockId;
    }

    /**
     * @notice Gets the finalized block reference
     * @param blockId The block identifier
     * @return The complete block reference with all metadata
     * @dev Only returns data for finalized blocks
     */
    function getBlockRef(uint256 blockId) external view returns (BlockRef memory) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.blocks[blockId];
    }

    //////////////////////
    // Voting and Block State
    //////////////////////
    
    /**
     * @notice Gets the relationship status between a validator and a specific block
     * @param blockId The block identifier
     * @param validator The validator address
     * @return Block state code:
     *         0 - No relationship with this block
     *         1 - Block is assigned to this validator (awaiting proposal)
     *         2 - This validator made the main proposal for this block
     *         3 - This validator made a discussion/alternative proposal for this block
     *         4 - This validator voted on this block
     *         5 - This block has been finalized
     * @dev Useful for UIs to show validator's involvement with specific blocks
     */
    function blockStateFor(uint256 blockId, address validator) external view returns (uint8) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();

        // Check if block is assigned to this validator
        if (state.queue[blockId] == validator) {
            return 1;
        }

        // Check if validator made a proposal for this block
        if (state.blockProposals[blockId][validator].createdBy != address(0)) {
            // Main proposer (first in array) vs discussion proposer
            if (state.blockProposers[blockId][0] == validator) {
                return 2;
            } else {
                return 3;
            }
        }

        // Check if validator voted on this block
        if (state.votes[blockId][validator] != address(0)) {
            return 4;
        }

        // Check if block is finalized
        if (state.blocks[blockId].createdBy != address(0)) {
            return 5;
        }

        return 0;
    }

    /**
     * @notice Checks if a block is ready for finalization and returns voting results
     * @param blockId The block identifier to check
     * @return winner The winning validator (address(0) if not ready)
     * @return voterCount Total number of voters
     * @return maxVotes Votes received by winner
     * @return subMaxVotes Votes received by second place
     * @return rest Remaining votes not cast
     * @dev Only works for the next block in finalization queue
     *      Returns voting statistics to help determine finalization readiness
     */
    function isFinalazible(uint256 blockId) external view returns (address, uint256, uint256, uint256, uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        if (blockId != state.nextFinalBlockId) {
            revert OpenStoreError(ERROR_BLOCK_ID_NOT_NEXT_TO_FINALIZE);
        }

        // Get voting configuration
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        uint256 blockWindow = config.voteBlockWindow;

        address[] memory proposers = state.blockProposers[blockId];

        // Calculate voting results
        (
            address winner,
            uint256 voterCount,
            uint256 maxVotes,
            uint256 subMaxVotes,
            uint256 rest,
            uint256 a,
            uint256 b
        ) = _calculateVotes(
            state, proposers, blockId, 0, blockWindow
        );

        return (winner, voterCount, maxVotes, subMaxVotes, rest);
    }

    function proposalBlockInfo(uint256 block_id, address validator) external view returns (
        uint256,
        uint256,
        uint256,
        uint256,

        bytes32,
        bytes memory,
        uint16,

        uint8,
        address
    ) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        BlockRef memory block = state.blockProposals[block_id][validator];

        return (
            block.id,
            block.fromRequestId,
            block.toRequestId,
            block.result,

            block.objectHash,
            block.objectId,
            block.protocolId,

            block.blockMask,
            block.createdBy
        );
    }

    // Requests
    function nextRequestIdToValidate() external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        return state.nextRequestId;
    }

    function leastRequestIdToFinalize() external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        uint256 lastBlockFinal = state.nextFinalBlockId - 1;
        uint256 requestId = state.blocks[lastBlockFinal].toRequestId;

        if (requestId == 0) {
            return 1;
        }

        return requestId;
    }

    function nextRequestIdToPropose() public view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        uint256 lastBlockProposal = state.nextProposalBlockId - 1; // nextProposalBlockId starts with 1
        if (lastBlockProposal == 0) {
            return 1;
        }

        uint256 lastBlockFinal = state.nextFinalBlockId - 1; // nextFinalBlockId starts with 1
        if (lastBlockFinal == lastBlockProposal) {
            return state.blocks[lastBlockFinal].toRequestId;
        }

        address[] storage proposers = state.blockProposers[lastBlockProposal];
        return state.blockProposals[lastBlockProposal][proposers[0]].toRequestId;
    }

    //////////////////////
    // Validator Management
    //////////////////////
    
    /**
     * @notice Checks if an address is a registered validator
     * @param validator The address to check
     * @return True if the address is a registered validator
     * @dev Validators must be registered to participate in validation and voting
     */
    function isValidatorRegistered(address validator) external view returns (bool) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        Validator storage validator = state.validators[validator];
        return validator.id > 0;
    }

    /**
     * @notice Registers the caller as a validator
     * @param validatorVersion The validator software version
     * @dev Requires sufficient stake (must call topUp first) and compatible version
     *      Adds validator to active set and enables participation in consensus
     */
    function registerValidator(uint64 validatorVersion) external {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        if (validatorVersion < config.minValidatorVersion) {
            revert OpenStoreError(ERROR_VALIDATOR_UNSUPPORTED_VERSION);
        }

        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        Validator storage validator = state.validators[msg.sender];
        if (validator.id != 0) {
            revert OpenStoreError(ERROR_VALIDATOR_ALREADY_REGISTERED);
        }

        uint256 minStakeAmount = config.minStakeAmount;
        uint256 totalBalance = validator.totalBalance;
        if (totalBalance < minStakeAmount) {
            revert OpenStoreError(ERROR_INSUFFICIENT_STAKE);
        }

        // Add to active validators array and assign ID
        state.activeValidators.push(msg.sender);
        validator.id = state.activeValidators.length - 1;
        validator.version = validatorVersion;
        validator.lastActivityBlockId = state.nextFinalBlockId; // Track activity from registration
        state.totalBalance += totalBalance;
    }

    /**
     * @notice Force unregister a validator due to inactivity.
     * Can be called by anyone. If the difference between the last finalized block and
     * validator's last activity block is greater than config.maxInactiveBlocks the
     * validator is unregistered and `overdueProposalFee` is paid to the sender as reward.
     */
    function unregisterInactiveValidator(address validatorAddr) external {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();

        Validator storage validator = state.validators[validatorAddr];

        uint256 nextFinalBlockId = state.nextFinalBlockId;
        uint256 lastActivityBlockId = validator.lastActivityBlockId;

        // Check inactivity window
        if (nextFinalBlockId < lastActivityBlockId || nextFinalBlockId - lastActivityBlockId <= config.maxInactiveBlocks) {
            revert OpenStoreError(ERROR_VALIDATOR_STILL_ACTIVE);
        }

        // Remove from activeValidators array
        unregisterValidator(state, validator, validatorAddr);

        uint256 rewardAmount = config.inactiveFee;
        if (rewardAmount > validator.balance) {
            rewardAmount = validator.balance;
        }

        // Slash validator balance and reward sender
        if (rewardAmount > 0) {
            Validator storage rewardValidator = state.validators[msg.sender];
            validator.balance -= rewardAmount;
            validator.totalBalance -= rewardAmount;
            rewardValidator.balance += rewardAmount;
            rewardValidator.totalBalance += rewardAmount;
        }

        emit ValidatorForceUnregistered(validatorAddr, msg.sender, rewardAmount);
    }

    function unregisterValidator() external {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        Validator storage validator = state.validators[msg.sender];
        unregisterValidator(state, validator, msg.sender);
    }

    function unregisterValidator(
        OpenStoreState storage state,
        Validator storage validator,
        address validatorAddr
    ) private {
        uint256 id = validator.id;
        if (id == 0) {
            revert OpenStoreError(ERROR_VALIDATOR_NOT_REGISTERED);
        }
        if (state.validatorLocker[validatorAddr] != 0) {
            revert OpenStoreError(ERROR_VALIDATOR_IN_QUEUE);
        }
        if (state.emergencyLocker[validatorAddr] != 0) {
            revert OpenStoreError(ERROR_VALIDATOR_IN_EMERGENCY_LOCK);
        }

        uint256 lastId = state.activeValidators.length - 1;
        if (id != lastId) {
            address lastValidator = state.activeValidators[lastId];
            state.activeValidators[id] = lastValidator;
            state.validators[lastValidator].id = id;
        }

        state.activeValidators.pop();
        validator.id = 0;
        state.totalBalance -= validator.totalBalance;
    }

    function assignBlockId(uint256 blockId) external {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        if (config.isQueueSuspended) {
            revert OpenStoreError(ERROR_QUEUE_SUSPENDED);
        }

        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        address validatorAddr = msg.sender;
        Validator storage validator = state.validators[validatorAddr];
        if (validator.id == 0) {
            revert OpenStoreError(ERROR_VALIDATOR_NOT_REGISTERED);
        }
        if (validator.version < config.minValidatorVersion) {
            revert OpenStoreError(ERROR_VALIDATOR_UNSUPPORTED_VERSION);
        }
        if (state.validatorLocker[validatorAddr] != 0) {
            revert OpenStoreError(ERROR_VALIDATOR_ALREADY_IN_QUEUE);
        }

        uint256 nextBlockId = state.nextBlockId;
        state.validatorLocker[validatorAddr] = nextBlockId;
        state.nextBlockId += 1;

        uint256 nextProposalBlockId = state.nextProposalBlockId;
        if (blockId != nextBlockId) {
            revert OpenStoreError(ERROR_BLOCK_ID_NOT_INCREMENTAL);
        }
        state.queue[blockId] = validatorAddr;

        // Check balance
        uint256 balance = validator.balance;
        uint256 unspendableAmount = config.basicAmount;
        uint256 proposalAmount = config.baseProposalAmount;
        if (balance < proposalAmount + unspendableAmount) {
            revert OpenStoreError(ERROR_INSUFFICIENT_BALANCE_FOR_PROPOSAL);
        }

        validator.balance -= proposalAmount;

        // If there's no any block competition, we can assign without votingBalance spending
        // Check voting balance
        // nextFinalBlockId can't be more than blockId
        if (config.maxParallelProposals <= (blockId - state.nextFinalBlockId)) {
            uint256 votesToEnqueue = votesToAssign(validatorAddr);
            uint256 votingBalance = validator.votingBalance;
            if (votingBalance < votesToEnqueue) {
                revert OpenStoreError(ERROR_INSUFFICIENT_VOTING_BALANCE);
            }
            validator.votingBalance -= votesToEnqueue;
        }

        // To prevent attack when last block was much time ago and after enqueueValidator someone will create proposal
        if (nextProposalBlockId == blockId) {
            state.nextProposalTimestampFrom = block.timestamp;
        }

        emit QueueChanged(blockId, validatorAddr);
    }

    function unassignBlockId(uint256 blockId) external {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        OpenStoreState storage state = OpenStoreStorage.openStoreState();

        address validatorAddr = msg.sender;

        if (blockId != state.validatorLocker[validatorAddr]) {
            revert OpenStoreError(ERROR_SENDER_NOT_BLOCK_OWNER);
        }

        if (blockId != state.nextBlockId - 1 && blockId != 0) {
            revert OpenStoreError(ERROR_CANNOT_UNASSIGN_BLOCK);
        }

        Validator storage validator = state.validators[validatorAddr];
        uint256 proposalAmount = config.baseProposalAmount;

        state.nextBlockId -= 1;
        state.validatorLocker[validatorAddr] = 0;
        state.queue[blockId] = address(0);
        validator.balance += proposalAmount;
    }

    /**
     * @notice Deposits ETH to increase validator's balance and stake
     * @dev Increases both available balance and total balance (stake)
     *      If validator is registered, also increases the total system balance
     *      Anyone can call this to stake ETH for validation participation
     */
    function topUp() external payable {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        address validatorAddr = msg.sender;

        Validator storage validator = state.validators[validatorAddr];
        validator.balance += msg.value;
        validator.totalBalance += msg.value;

        // Update system total if validator is registered
        if (validator.id > 0) {
            state.totalBalance += msg.value;
        }
    }

    /**
     * @notice Withdraws ETH from validator's balance
     * @param amount The amount to withdraw in wei
     * @dev Registered validators must maintain minimum stake amount
     *      Reduces both available balance and total balance (stake)
     *      Automatically updates system totals for registered validators
     */
    function withdraw(uint256 amount) external payable {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        address validatorAddr = msg.sender;

        Validator storage validator = state.validators[validatorAddr];
        if (validator.balance < amount) {
            revert OpenStoreError(ERROR_INSUFFICIENT_BALANCE);
        }

        // Ensure registered validators maintain minimum stake
        if (validator.id > 0 && (validator.totalBalance - amount) < config.minStakeAmount) {
            revert OpenStoreError(ERROR_INSUFFICIENT_STAKE);
        }

        validator.balance -= amount;
        validator.totalBalance -= amount;

        // Update system total if validator is registered
        if (validator.id > 0) {
            state.totalBalance -= amount;
        }

        payable(validatorAddr).transfer(amount);
    }

    //////////////////////
    // Request Management
    //////////////////////

    /**
     * @notice Submits a validation request to the OpenStore
     * @param reqType The type of request (e.g., app submission, update, etc.)
     * @param target The target contract address for the request
     * @param data The request-specific data payload
     * @dev Requires payment of validation fees based on request type
     *      Requests are queued for validator processing and consensus
     */
    function addValidationRequest(uint256 reqType, address target, bytes calldata data) external payable {
        _addValidationRequest(msg.sender, msg.value, reqType, target, data);
    }

    /**
     * @notice Submits a validation request via multicall (internal use)
     * @param sender The original sender of the request
     * @param reqType The type of request
     * @param target The target contract address
     * @param data The request data
     * @dev Only callable through trusted multicall contracts
     */
    function addValidationRequest(
        address sender,
        uint256 reqType,
        address target,
        bytes calldata data
    ) onlyMulticall external payable {
        _addValidationRequest(sender, msg.value, reqType,  target, data);
    }

    /**
     * @notice Internal function to process validation requests
     * @param sender The request originator
     * @param msgValue The payment amount
     * @param reqType The request type
     * @param target The target contract
     * @param data The request data
     * @dev Delegates to request handler for processing and emits NewRequest event
     */
    function _addValidationRequest(
        address sender,
        uint256 msgValue,
        uint256 reqType,
        address target,
        bytes calldata data
    ) private {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        bytes memory callData = abi.encodeCall(
            IOpenStoreRequestHandler.onAddValidationRequest,
            (sender, msgValue, reqType, target, data)
        );

        bytes memory result = Address.functionDelegateCall(config.requestHandler, callData);

        emit OpenStore.NewRequest(target, result.toUint256(0), reqType, data);
    }

    /**
     * @notice Retrieves a validation request by ID
     * @param requestId The request identifier
     * @return reqType The request type
     * @return target The target contract address
     * @return data The request data payload
     * @dev Used to examine queued requests before validation
     */
    function getRequest(uint256 requestId) external view returns (uint256, address, bytes memory) {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        RequestInfo memory info = state.requests[requestId];
        return (info.reqType, info.target, info.data);
    }

    //////////////////////
    // Voting and Consensus
    //////////////////////
    
    /**
     * @notice Proposes a block containing validation results for a batch of requests
     * @param blockRef The complete block proposal with metadata and validation results
     * @dev This is the core consensus mechanism function where validators propose their
     *      validation results for batches of requests. Other validators then vote on these proposals.
     *      
     *      Two types of proposals:
     *      1. Main proposals: First proposal for a block (requires block assignment)
     *      2. Discussion proposals: Alternative proposals (requires emergency lock and fee)
     *      
     *      Main proposals advance the chain, discussions provide alternatives for voting
     */
    function proposeBlock(
        BlockRef memory blockRef
    ) external {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        uint256 blockId = blockRef.id;
        address proposer = msg.sender;
        bool isDiscussion = blockRef.blockMask & BI_MASK_IS_DISCUSSION == 1;

        if (blockRef.toRequestId <= blockRef.fromRequestId) {
            revert OpenStoreError(ERROR_INVALID_REQUEST_ID_RANGE);
        }
        if ((blockRef.toRequestId - blockRef.fromRequestId) > config.maxReqPerBlock) {
            revert OpenStoreError(ERROR_TOO_MANY_REQUESTS_IN_BLOCK);
        }
        if (proposer != blockRef.createdBy) {
            revert OpenStoreError(ERROR_SENDER_NOT_BLOCK_OWNER);
        }

        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        if (state.nextRequestId < blockRef.toRequestId) {
            revert OpenStoreError(ERROR_INVALID_TO_REQUEST_ID);
        }
        if (state.blockProposals[blockId][proposer].id != 0) {
            revert OpenStoreError(ERROR_PROPOSAL_VALIDATOR_ALREADY_EXISTS);
        }

        if (state.blockProposalsHashes[blockId][blockRef.objectHash]) {
            revert OpenStoreError(ERROR_PROPOSAL_HASH_ALREADY_EXISTS);
        }

        uint256 baseProposalAmount = config.baseProposalAmount;

        Validator storage validator = state.validators[proposer];
        // Update last activity
        validator.lastActivityBlockId = blockId;
        if (validator.id == 0) {
            revert OpenStoreError(ERROR_VALIDATOR_NOT_REGISTERED);
        }
        if (validator.version < config.minValidatorVersion) {
            revert OpenStoreError(ERROR_VALIDATOR_UNSUPPORTED_VERSION);
        }

        if (isDiscussion) {
            if (state.emergencyLocker[proposer] != 0) {
                revert OpenStoreError(ERROR_VALIDATOR_IN_EMERGENCY_LOCK);
            }
            if (state.blockProposers[blockId].length == 0) {
                revert OpenStoreError(ERROR_NO_PROPOSAL_TO_DISCUSS);
            }
            if (validator.balance < baseProposalAmount) {
                revert OpenStoreError(ERROR_INSUFFICIENT_BALANCE_FOR_PROPOSAL);
            }

            address mainProposer = state.blockProposers[blockId][0];
            if (state.blockProposals[blockId][mainProposer].result == blockRef.result) {
                revert OpenStoreError(ERROR_DISCUSSION_RESULT_SAME);
            }
            if (state.blockProposals[blockId][mainProposer].fromRequestId != blockRef.fromRequestId) {
                revert OpenStoreError(ERROR_DISCUSSION_FROM_REQ_ID_MISMATCH);
            }
            if (state.blockProposals[blockId][mainProposer].toRequestId != blockRef.toRequestId) {
                revert OpenStoreError(ERROR_DISCUSSION_TO_REQ_ID_MISMATCH);
            }
            if (state.votes[blockId][proposer] != address(0)) {
                revert OpenStoreError(ERROR_CANNOT_DISCUSS_AFTER_VOTE);
            }

            validator.balance -= baseProposalAmount;
            state.emergencyLocker[proposer] = blockId;
        } else {
            if (nextRequestIdToPropose() != blockRef.fromRequestId) {
                revert OpenStoreError(ERROR_INVALID_FROM_REQUEST_ID);
            }

            if (state.proposalsOnVoting > config.maxParallelProposals) {
                revert OpenStoreError(ERROR_MAX_PARALLEL_PROPOSALS_REACHED);
            }
            if (blockId != state.nextProposalBlockId) {
                revert OpenStoreError(ERROR_BLOCK_ID_NOT_NEXT_TO_PROPOSE);
            }

            address mainProposer = state.queue[blockId];
            if (block.timestamp - state.nextProposalTimestampFrom <= config.proposalBlockWindow) {
                if (proposer != mainProposer) {
                    revert OpenStoreError(ERROR_SENDER_NOT_BLOCK_OWNER);
                }
            } else if (proposer != mainProposer) {
                if (state.emergencyLocker[proposer] != 0) {
                    revert OpenStoreError(ERROR_VALIDATOR_IN_EMERGENCY_LOCK);
                }
                if (validator.balance < baseProposalAmount) {
                    revert OpenStoreError(ERROR_INSUFFICIENT_BALANCE_FOR_PROPOSAL);
                }

                state.validators[mainProposer].balance += baseProposalAmount - config.overdueProposalFee;
                state.validators[mainProposer].totalBalance -= config.overdueProposalFee;
                state.totalBalance -= config.overdueProposalFee;

                validator.balance -= baseProposalAmount;
                state.emergencyLocker[proposer] = blockId;
            }

            state.nextProposalTimestampFrom = block.timestamp;
        }

        state.blockProposalsHashes[blockId][blockRef.objectHash] = true;
        state.blockProposals[blockId][proposer] = blockRef;
        state.blockProposers[blockId].push(proposer);
        state.proposalVotingCreatedAt[blockId] = block.timestamp;

        if (!isDiscussion) {
            state.proposalsOnVoting++;
            state.nextProposalBlockId++;
            delete state.queue[blockId];
        }

        emit BlockProposed(blockId, proposer, blockRef.fromRequestId, blockRef.toRequestId, isDiscussion);
    }

    /**
     * @notice Votes for a validator's proposal on a specific block
     * @param blockId The block identifier being voted on
     * @param validator The validator whose proposal is being supported
     * @param unavailabilityMask Bitmask indicating which requests in the block are considered unavailable
     * @dev Validators vote to support proposals they agree with. Voting requires:
     *      - Voter must be registered and up-to-date
     *      - Cannot vote for yourself
     *      - Must pay voting fee
     *      - Voting window must be open
     *      - Each validator can only vote once per block
     *      
     *      The unavailabilityMask allows voters to indicate disagreement with specific
     *      request validations while supporting the overall proposal
     */
    function vote(uint256 blockId, address validator, uint128 unavailabilityMask) external {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        address voterAddr = msg.sender;

        Validator storage voter = state.validators[voterAddr];
        // Update last activity
        voter.lastActivityBlockId = blockId;
        if (voter.id == 0) {
            revert OpenStoreError(ERROR_VOTER_NOT_REGISTERED);
        }
        if (voter.version < config.minValidatorVersion) {
            revert OpenStoreError(ERROR_VALIDATOR_UNSUPPORTED_VERSION);
        }
        if (validator == voterAddr) {
            revert OpenStoreError(ERROR_CANNOT_VOTE_FOR_SELF);
        }
        if (state.blockProposals[blockId][validator].createdBy == address(0)) {
            revert OpenStoreError(ERROR_PROPOSAL_NOT_FOUND);
        }
        uint256 votingClosingTime = state.proposalVotingCreatedAt[blockId] + config.voteBlockWindow;
        if (block.timestamp > votingClosingTime) {
            revert OpenStoreError(ERROR_VOTING_PERIOD_CLOSED);
        }
        uint256 voteAmount = config.baseVoteAmount;
        if (voter.balance < voteAmount) {
            revert OpenStoreError(ERROR_INSUFFICIENT_BALANCE_FOR_VOTE);
        }
        if (state.votes[blockId][voterAddr] != address(0)) {
            revert OpenStoreError(ERROR_ALREADY_VOTED);
        }

        state.blockVoters[blockId][validator].push(voterAddr);
        state.votes[blockId][voterAddr] = validator;
        voter.balance -= voteAmount;
        voter.votingBalance += PRECISION_SCALE_AND_VOTE_UNIT;

        if (unavailabilityMask > 0) {
            state.masks[blockId][voterAddr] = unavailabilityMask;
        }

        emit ValidatorVoted(blockId, validator, voterAddr);
    }

    //////////////////////
    // Block Finalization
    //////////////////////
    
    /**
     * @notice Finalizes a block after voting is complete
     * @param blockId The block identifier to finalize
     * @dev This function completes the consensus process by:
     *      1. Calculating vote results and determining the winner
     *      2. Processing validation results for all requests in the block
     *      3. Distributing rewards to winners and slashing losers
     *      4. Updating the vault with validated assets
     *      5. Advancing the finalization chain
     *      
     *      Can only be called for the next block in the finalization queue
     *      and only after sufficient voting has occurred to determine a clear winner
     */
    function finalizeBlock(uint256 blockId) external {
        uint256 gasLeft = gasleft();
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        if (blockId != state.nextFinalBlockId) {
            revert OpenStoreError(ERROR_BLOCK_ID_NOT_NEXT_TO_FINALIZE);
        }

        // Calculate reward
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        uint256 voteBlockWindow = config.voteBlockWindow;

        address[] memory proposers = state.blockProposers[blockId];

        BlockRef storage preInfo = state.blockProposals[blockId][proposers[0]];
        uint256 reqCount = preInfo.toRequestId - preInfo.fromRequestId;
        (
            address winner,
            uint256 a,
            uint256 b,
            uint256 c,
            uint256 d,
            uint256 unavailabilityVotersSnapshot,
            uint256 unavailableRequestCount
        ) = _calculateVotes(
            state, proposers, blockId, reqCount, voteBlockWindow
        );

        if (winner == address(0)) {
            revert OpenStoreError(ERROR_PROPOSAL_NOT_READY_TO_FINALIZE);
        }

        BlockRef memory info = state.blockProposals[blockId][winner];
        info.result &= unavailabilityVotersSnapshot;

        // Calculate reward
        uint256 requestsCount = (info.toRequestId - info.fromRequestId) - unavailableRequestCount; // checked on proposeBlock stage
        uint256 requestRewards = requestsCount * config.validationRequestAmount;
        uint256 requestLose = unavailableRequestCount * config.validationRequestAmount;

        // Reward winners
        uint256 voteAmount = config.baseVoteAmount;
        uint256 proposalAmount = config.baseProposalAmount;
        uint256 reminder = _slashAndReward(
            state, proposers, blockId, winner, info.result, requestRewards,
            voteAmount, proposalAmount
        );

        // Update store vault
        uint256 result = info.result;
        uint256 count = info.toRequestId - info.fromRequestId;

        bytes memory callData = abi.encodeCall(
            IOpenStoreRequestHandler.onRemoveValidationRequests,
            (result, count, info.fromRequestId)
        );
        Address.functionDelegateCall(config.requestHandler, callData);

        // Submission
        state.blocks[blockId] = info;
        state.nextFinalRequestId = info.toRequestId;
        state.nextFinalBlockId++;

        if (reminder > 0) {
            state.totalBalance -= reminder;
            state.contractBalance += reminder + requestLose;
        }

        if (state.proposalsOnVoting == config.maxParallelProposals) {
            state.nextProposalTimestampFrom = block.timestamp;
        }
        state.proposalsOnVoting--;

        delete state.proposalVotingCreatedAt[blockId];
        delete state.validatorLocker[state.blockProposers[blockId][0]];
        delete state.emergencyLocker[state.blockProposers[blockId][0]];
        delete state.blockProposers[blockId];

        emit BlockFinalized(blockId, winner, info.objectId);
    }

    /**
     * @notice Helper function to calculate the total votes for a single proposer and update unavailability votes.
     * @dev This function isolates the logic of iterating through a proposer's voters, reducing stack depth in the main function.
     * @param state The storage state.
     * @param proposer The address of the proposer whose votes are being calculated.
     * @param blockId The ID of the block being voted on.
     * @param unavailableReqVotes A memory array to accumulate votes for unavailable requests.
     * @return votesCounter The total votes (self-stake + voters' stake) for the given proposer.
     */
    function _getProposerVotesAndMasks(
        OpenStoreState storage state,
        address proposer,
        uint256 blockId,
        uint256[] memory unavailableReqVotes
    ) private view returns (uint256) {
        uint256 proposerVotePower = state.validators[proposer].totalBalance;
        uint256 votesCounter = proposerVotePower;
        address[] memory voters = state.blockVoters[blockId][proposer];

        for (uint256 y = 0; y < voters.length; y++) {
            address voter = voters[y];
            uint256 voterPower = state.validators[voter].totalBalance;
            votesCounter += voterPower;

            uint128 mask = state.masks[blockId][voter];
            if (mask > 0) {
                for (uint256 bit = 0; bit < unavailableReqVotes.length; bit++) {
                    if ((mask >> bit) & 1 == 1) {
                        // This modification to a memory array passed by reference is key.
                        unavailableReqVotes[bit] += voterPower;
                    }
                }
            }
        }

        // TODO check correctness
        uint256 proposerResultMask = state.blockProposals[blockId][proposer];
        for (uint256 bit = 0; bit < unavailableReqVotes.length; bit += 2) {
            if ((proposerResultMask >> bit) & 2 == 0) { // 2 -- 0x11 so both bytes will be covered
                // This modification to a memory array passed by reference is key.
                unavailableReqVotes[bit] += proposerVotePower;
            }
        }

        return votesCounter;
    }

    /**
     * @notice Helper function to calculate the final unavailability snapshot based on voting results.
     * @dev Isolates the final calculation loop, further reducing stack depth.
     * @param state The storage state.
     * @param winner The address of the winning proposer.
     * @param blockId The ID of the block.
     * @param totalVotes The total votes cast in the election.
     * @param unavailableReqVotes A memory array containing the accumulated votes for unavailable requests.
     * @return votingUnavailabilitySnapshot The calculated snapshot mask.
     * @return unavailableRequestCount The count of requests marked as unavailable.
     */
    function _calculateUnavailabilitySnapshot(
        OpenStoreState storage state,
        address winner,
        uint256 blockId,
        uint256 totalVotes,
        uint256[] memory unavailableReqVotes
    ) private view returns (uint256, uint256) {
        // snapshot - mask of states 0b00 if unavailable and 0b11 for any other
        uint256 votingUnavailabilitySnapshot = type(uint256).max;
        uint256 unavailableRequestCount = 0;

        // No need to calculate if there's no winner or no requests to check.
        if (winner == address(0) || unavailableReqVotes.length == 0) {
            return (votingUnavailabilitySnapshot, 0);
        }

        uint256 winnerMask = state.blockProposals[blockId][winner].result;
        uint256 threshold = totalVotes / 2;

        for (uint256 i = 0; i < unavailableReqVotes.length; i++) {
            if (unavailableReqVotes[i] > threshold) {
                // Set the corresponding 2 bits to 00 in the snapshot to mark as unavailable.
                votingUnavailabilitySnapshot ^= (3 << (i * 2)); // 3 is 0b11
                unavailableRequestCount += 1;
            }
        }

        return (votingUnavailabilitySnapshot, unavailableRequestCount);
    }

    /**
     * @notice Calculates the winning proposer and voting results for a given block.
     * @dev Refactored to prevent "Stack Too Deep" errors by using helper functions.
     */
    function _calculateVotes(
        OpenStoreState storage state,
        address[] memory proposers,
        uint256 blockId,
        uint256 blockReqCount,
        uint256 blockWindow
    ) private view returns (address, uint256, uint256, uint256, uint256, uint256, uint256) {
        // --- Part 1: Vote Counting and Winner Determination ---
        uint256 maxVotes = 0;
        uint256 subMaxVotes = 0;
        uint256 totalVotes = 0;
        address winner = address(0);
        uint256[] memory unavailableReqVotes = new uint256[](blockReqCount);

        for (uint256 i = 0; i < proposers.length; i++) {
            address proposer = proposers[i];

            // Call helper to get votes for this proposer and update unavailability votes
            uint256 votesCounter = _getProposerVotesAndMasks(
                state,
                proposer,
                blockId,
                unavailableReqVotes
            );

            if (votesCounter > maxVotes) {
                subMaxVotes = maxVotes;
                maxVotes = votesCounter;
                winner = proposer;
            } else if (votesCounter > subMaxVotes) {
                subMaxVotes = votesCounter;
            }

            totalVotes += votesCounter;
        }

        // --- Part 2: Winner Confirmation (Separation Check) ---
        uint256 rest = 0;
        uint256 maxTotalVotes = state.totalBalance;
        if (block.timestamp - state.proposalVotingCreatedAt[blockId] < blockWindow) {
            uint256 separation = maxVotes - subMaxVotes;
            rest = maxTotalVotes - totalVotes;

            if (rest > separation) {
                // Not enough separation, the outcome is uncertain. Nullify the winner.
                winner = address(0);
            }
        }

        // --- Part 3: Unavailability Snapshot Calculation ---
        uint256 votingUnavailabilitySnapshot;
        uint256 unavailableRequestCount;

        (votingUnavailabilitySnapshot, unavailableRequestCount) = _calculateUnavailabilitySnapshot(
            state,
            winner,
            blockId,
            totalVotes,
            unavailableReqVotes
        );

        return (winner, maxTotalVotes, maxVotes, subMaxVotes, rest, votingUnavailabilitySnapshot, unavailableRequestCount);
    }

    /**
     * @notice Handles reward distribution and slashing after block finalization
     * @param state The storage state containing all validator and voting data
     * @param proposers Array of all validators who made proposals for this block
     * @param blockId The block identifier being finalized
     * @param winner The validator whose proposal won the consensus vote
     * @param winnerResult The bitmask result from the winning proposal
     * @param requestRewards Total rewards from successfully processed requests
     * @param voteAmount The base voting fee amount
     * @param proposalAmount The base proposal fee amount
     * @return reminder Any remaining funds after equal distribution (due to rounding)
     * @dev This function implements the core economic incentive mechanism:
     *      
     *      **Reward Logic:**
     *      - Winner gets: proposal fee back + request rewards + share of slashed funds
     *      - Winner's voters get: vote fee back + share of slashed funds
     *      - Compatible proposers get: proposal fee back (no slashing)
     *      - Compatible voters get: vote fee back (no slashing)
     *      
     *      **Slashing Logic:**
     *      - Incompatible proposers lose: proposal fee (slashed from totalBalance)
     *      - Incompatible voters lose: vote fee (slashed from totalBalance)
     *      
     *      **Distribution:**
     *      - All slashed funds are pooled and distributed equally among winner + winner's voters
     *      - Compatible proposals are determined using bitmask comparison (compareMasks)
     *      - This allows proposals with similar results to avoid slashing
     *      
     *      **Gas Optimization:**
     *      - Cleans up all proposal and voting storage to refund gas
     *      - Uses two-pass algorithm to minimize storage operations
     */
    function _slashAndReward(
        OpenStoreState storage state,
        address[] memory proposers,
        uint256 blockId,
        address winner,
        uint256 winnerResult,
        uint256 requestRewards,
        uint256 voteAmount,
        uint256 proposalAmount
    ) private returns (uint256) {
        uint256 slashVotersCount;
        uint256 slashProposersCount;
        for (uint256 i = 0; i < proposers.length; i++) {
            address proposer = proposers[i];

            if (proposer == winner) {
                continue;
            }

            uint256 result = state.blockProposals[blockId][proposer].result;
            if (result.compareMasks(winnerResult)) {
                state.validators[proposer].balance += proposalAmount;

                address[] memory voters = state.blockVoters[blockId][proposer];
                for (uint256 y = 0; y < voters.length; y++) {
                    state.validators[voters[y]].balance += voteAmount;
                    delete state.votes[blockId][voters[y]];
                }

                bytes32 hash = state.blockProposals[blockId][proposer].objectHash;
                delete state.blockProposalsHashes[blockId][hash];
                delete proposers[i];
                delete state.blockVoters[blockId][proposer];
                delete state.blockProposals[blockId][proposer];
            } else {
                slashVotersCount += state.blockVoters[blockId][proposer].length;
                slashProposersCount += 1;
            }
        }

        uint256 rewardPerWinner;
        uint256 reminder;
        if (state.blockProposers[blockId].length > 1) {
            uint256 totalSlashingReward = (slashProposersCount * proposalAmount) + (slashVotersCount * voteAmount);
            uint256 winnerVotersCount = state.blockVoters[blockId][winner].length;
            uint256 winnerCount = winnerVotersCount + 1;

            rewardPerWinner = totalSlashingReward / winnerCount; // with winner
            reminder = totalSlashingReward % winnerCount;
        }

        // Slashing + Distribution
        for (uint256 i = 0; i < proposers.length; i++) {
            address proposer = proposers[i];
            if (proposer == address(0)) { // Already deleted in previous iteration
                continue;
            }

            if (proposer == winner) {
                state.validators[winner].blocksCreated++;
                uint256 totalReward = requestRewards + rewardPerWinner;
                state.validators[winner].balance += totalReward + proposalAmount;
                state.validators[winner].totalBalance += totalReward;
                state.totalBalance += requestRewards;
            } else {
                state.validators[proposer].totalBalance -= proposalAmount;
                // do not return stake to proposal
            }

            address[] memory voters = state.blockVoters[blockId][proposer];
            for (uint256 y = 0; y < voters.length; y++) {
                if (proposer == winner) {
                    state.validators[voters[y]].balance += rewardPerWinner + voteAmount;
                    state.validators[voters[y]].totalBalance += rewardPerWinner;
                } else {
                    state.validators[voters[y]].totalBalance -= voteAmount;
                }

                delete state.votes[blockId][voters[y]];
            }

            bytes32 hash = state.blockProposals[blockId][proposer].objectHash;
            delete state.blockProposalsHashes[blockId][hash];
            delete state.blockProposals[blockId][proposer];
            delete state.blockVoters[blockId][proposer];
        }

        return reminder;
    }

    //////////////////////
    // Distribution Track Management
    //////////////////////

    /**
     * @notice Adds a build version to a distribution track
     * @param target The target asset contract address
     * @param trackId The distribution track identifier (e.g., 1=stable, 2=beta, 3=alpha)
     * @param versionCode The build version code to add to the track
     * @dev Only the asset owner can manage their distribution tracks
     *      Tracks allow different release channels (stable, beta, etc.)
     *      Version codes must increase (no downgrades allowed)
     *      Track ID must be non-zero
     */
    function addBuildToTrack(address target, uint256 trackId, uint256 versionCode) external {
        _addBuildToTrack(msg.sender, target, trackId, versionCode);
    }

    function addBuildToTrack(address sender, address target, uint256 trackId, uint256 versionCode) external onlyMulticall {
        _addBuildToTrack(sender, target, trackId, versionCode);
    }

    function _addBuildToTrack(address sender, address target, uint256 trackId, uint256 versionCode) internal {
        if (sender != PluginOwnable(target).owner()) {
            revert OpenStoreError(ERROR_NOT_TARGET_OWNER);
        }

        OpenStoreVault storage vault = OpenStoreStorage.openStoreVault();
        if (trackId == 0) {
            revert OpenStoreError(ERROR_INVALID_TRACK_ID);
        }

        if (vault.tracks[target][trackId] > versionCode) {
            revert OpenStoreError(ERROR_BUILD_VERSION_DOWNGRADED);
        }

        vault.tracks[target][trackId] = versionCode;
        emit AddedToTrack(target, trackId, versionCode);
    }
}
