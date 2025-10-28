// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {VersionableOwner} from "../interfaces/VersionableOwner.sol";
import {Trustable} from "../multicall/Trustable.sol";
import {PluginManager} from "../plugin/PluginManager.sol";
import {PluginOwnable} from "../plugin/PluginOwnable.sol";

/**
 * @title IAssetlinksOracle
 * @dev Interface for the assetlinks verification oracle
 */
interface IAssetlinksOracle {
    /**
     * @dev Returns the last verified version for a target contract
     * @param target The contract address to check
     * @return The last verified version number, or 0 if not verified
     */
    function getLastVerifiedAssetVersion(address target) external view returns (uint256);
}

/**
 * @dev Represents the verification state for a contract
 * @param version The version number that was verified
 * @param status The verification status (1 = success, other = failure)
 */
struct VerificationState {
    uint256 version;
    uint256 status;
}

/**
 * @dev Represents a pending verification request
 * @param target The contract address to verify
 * @param version The version number to verify
 */
struct VerificationRequest {
    address target;
    uint256 version;
}

/**
 * @dev Complete verification information for a contract
 * @param last The last completed verification state
 * @param pendingVersion The version currently pending verification (0 if none)
 */
struct VerificationSet {
    VerificationState last;
    uint256 pendingVersion;
}

/**
 * @title AssetlinksOracle
 * @dev Oracle contract for verifying app ownership through Digital Asset Links
 * @notice Provides a queue-based verification system with fee requirements
 */
contract AssetlinksOracle is PluginManager, IAssetlinksOracle {

    /// @dev Custom error for oracle-related failures
    /// @param code Error code indicating the specific failure type
    error AssetlinksOracleError(uint32 code);
    uint32 constant private ADDRESS_ZERO = 1;
    uint32 constant private INSUFFICIENT_FEE = 2;
    uint32 constant private INVALID_VERSION = 3;
    uint32 constant private ALREADY_IN_REVIEW = 4;
    uint32 constant private INVALID_REQUEST_ID = 5;

    /// @dev Emitted when a verification request is queued
    /// @param app The app contract address
    /// @param version The version to be verified
    /// @param requestId The unique request identifier
    event EnqueueVerification(address app, uint256 version, uint256 requestId);
    
    /// @dev Emitted when a verification is completed
    /// @param app The app contract address
    /// @param version The verified version
    /// @param status The verification result status
    event FinalizeVerification(address app, uint256 version, uint256 status);

    // Const
    uint256 constant private SUCCESS_STATUS = 1;

    // State
    uint256 private verificationAmount;

    mapping(uint256 => VerificationRequest) public queue; // reqId -> req
    mapping(address => uint256) public pendingVersions; // asset - version
    uint256 public nextQueueRequestId;

    mapping(address => mapping(uint256 => uint256)) public states; // asset - version - status
    mapping(address => uint256) public lastVersions; // asset - version
    mapping(address => mapping(uint256 => uint256)) public lastSuccessAt; // asset - version - timestamp
    uint256 public lastVerifiedRequestId;

    /**
     * @dev Initializes the oracle with verification fee amount
     * @param _verificationAmount The fee required for each verification request
     */
    constructor(uint256 _verificationAmount) PluginManager(msg.sender) {
        verificationAmount = _verificationAmount;
        lastVerifiedRequestId = 0;
        nextQueueRequestId = 1;
    }

    /**
     * @dev Returns the fee required for verification requests
     * @return The verification fee amount in wei
     */
    function getVerificationAmount() external view returns (uint256) {
        return verificationAmount;
    }

    /**
     * @dev Sets the fee required for each verification request (owner only)
     * @param _verificationAmount The fee required for each verification request
     */
    function setVerificationAmount(uint256 _verificationAmount) external onlyOwner {
        verificationAmount = _verificationAmount;
    }

    /**
     * @dev Returns the current state of the oracle contract
     * @return lastVerifiedRequestId The ID of the last processed request
     * @return nextQueueRequestId The ID that will be assigned to the next request
     * @return blockNumber The current block number
     */
    function getContractState() external view returns (uint256, uint256, uint256) {
        return (lastVerifiedRequestId, nextQueueRequestId, block.number);
    }

    /**
     * @dev Returns the verification status for a given contract
     * @param obj The contract address to check
     * @return status The last verification status
     * @return time Delta between last success status and now
     */
    function getAssetStatus(address obj, uint256 version) external view returns (uint256, uint256) {
        uint256 lastSuccessAt = lastSuccessAt[obj][version];
        if (lastSuccessAt > 0) {
            lastSuccessAt = block.timestamp - lastSuccessAt;
        }

        return (states[obj][version], lastSuccessAt);
    }

    /**
     * @dev Returns the verification status for a given contract
     * @param obj The contract address to check
     * @return status The last verification status
     * @return version The last verified version
     * @return pendingVersion The version currently pending verification
     */
    function getLastAssetState(address obj) external view returns (uint256, uint256, uint256) {
        uint256 version = lastVersions[obj];
        uint256 status = states[obj][version];
        uint256 pendingVersion = pendingVersions[obj];
        return (status, version, pendingVersion);
    }

    /**
     * @dev Returns the last verified version if it matches the current contract version
     * @param target The contract address to check
     * @return The verified version number, or 0 if not currently verified
     */
    function getLastVerifiedAssetVersion(address target) external view override returns (uint256) {
        VersionableOwner plugin = VersionableOwner(target);
        uint256 version = plugin.ownerVersion();
        uint256 status = states[target][version];

        if (status == SUCCESS_STATUS) {
            return version;
        }

        return 0;
    }

    //////////////////
    //////////////////
    //////////////////
    /**
     * @dev Enqueues a verification request for the specified contract
     * @param obj The contract address to verify
     * @notice Requires payment of the verification fee
     */
    function enqueue(address obj) external payable {
        _enqueue(obj);
    }

    /**
     * @dev Enqueues a verification request via multicall
     * @param sender The address initiating the multicall (unused)
     * @param obj The contract address to verify
     */
    function enqueue(address sender, address obj) external payable onlyMulticall {
        _enqueue(obj);
    }

    /**
     * @dev Internal function to enqueue a verification request
     * @param obj The contract address to verify
     */
    function _enqueue(address obj) private {
        uint256 requestId = nextQueueRequestId;

        if (obj == address(0)) {
            revert AssetlinksOracleError(ADDRESS_ZERO);
        }

        if (msg.value < verificationAmount) {
            revert AssetlinksOracleError(INSUFFICIENT_FEE);
        }

        VersionableOwner plugin = VersionableOwner(obj);
        uint256 version = plugin.ownerVersion();
        if (version == 0) {
            revert AssetlinksOracleError(INVALID_VERSION);
        }

        uint256 pendingVersion = pendingVersions[obj];
        if (pendingVersion != 0) {
            revert AssetlinksOracleError(ALREADY_IN_REVIEW);
        }

        queue[requestId] = VerificationRequest(obj, version);
        pendingVersions[obj] = version;
        nextQueueRequestId = requestId + 1;

        emit EnqueueVerification(obj, version, requestId);
    }

    //////////////////
    //////////////////
    //////////////////
    /**
     * @dev Modifier to ensure requests are processed in order
     * @param requestId The request ID to process
     */
    modifier finishRequest(uint256 requestId) {
        uint256 next = lastVerifiedRequestId + 1;
        if (next != requestId) {
            revert AssetlinksOracleError(INVALID_REQUEST_ID);
        }

        _;

        lastVerifiedRequestId = requestId;
    }

    /**
     * @dev Finalizes a verification request with the given status
     * @param requestId The request ID to finalize
     * @param status The verification status (1 = success, other = failure)
     * @notice Only callable by the contract owner and requests must be processed in order
     */
    function finish(
        uint256 requestId,
        uint256 status
    ) external onlyOwner finishRequest(requestId) {
        VerificationRequest storage request = queue[requestId];
        address obj = request.target;
        uint256 version = request.version;

        uint256 oldStatus = states[obj][version];
        if (oldStatus == 1 || status == 1) {
            lastSuccessAt[obj][version] = block.timestamp;
        }

        states[obj][version] = status;
        lastVersions[obj] = version;

        delete queue[requestId];
        delete pendingVersions[obj];
        emit FinalizeVerification(obj, version, status);
    }
}
