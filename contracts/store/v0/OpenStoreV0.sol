// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../../libs/BitPacking.sol";
import "../../libs/BitmaskComparator.sol";
import "../../libs/BytesParser.sol";
import "../../oracle/AssetlinksOracle.sol";
import "../../plugin/PluginOwnable.sol";
import "../IOpenStoreRequestHandler.sol";
import "./OpenStoreStorageV0.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {PluginDelegatedOwner} from "../../plugin/delegate/PluginDelegatedOwner.sol";

/**
 * @title OpenStoreV2
 * @dev Next-generation OpenStore contract with simplified per-request voting and rewards
 * @notice Validators vote on individual requests within a fixed window; rewards are claimable per-validator
 */
contract OpenStoreV0 is PluginManager {

    using BytesParser for bytes;

    uint16 private constant ERROR_NOT_TARGET_OWNER = 17;
    error OpenStoreError(uint16 code);

    constructor(
        address _owner,
        OpenStoreConfigV0 memory _config
    ) PluginManager(_owner) {
        OpenStoreStateV0 storage state = OpenStoreStorageV0.openStoreState();
        state.nextRequestIdToCreate = 1;

        OpenStoreConfigV0 storage cfg = OpenStoreStorageV0.openStoreConfig();
        OpenStoreStorageV0.setStoreConfig(cfg, _config);
    }

    event ConfigChanged();

    event AppVisibilityChanged(address indexed target, bool isVisible);

    /// @notice Emitted when a new validation request is submitted
    /// @param target The target contract address
    /// @param requestId The unique request identifier
    /// @param reqType The type of request
    /// @param data The request data
    event NewRequest(address indexed target, uint256 requestId, uint256 reqType, bytes data);

    //////////////////////
    // Vault Management - Asset and Build Tracking
    //////////////////////

    /**
     * @notice Checks if a build version is verified against the current owner version
     * @param target The asset contract address
     * @param versionCode The build version to check
     * @return True if the build matches the current owner version
     * @dev Compares stored build ownership version with current asset owner version
     */
    function isOwnershipVersionActual(address target, uint256 versionCode) external view returns (bool) {
        VersionableOwner owner = VersionableOwner(target);
        OpenStoreVaultV0 storage vault = OpenStoreStorageV0.openStoreVault();
        return vault.builds[target][versionCode] == owner.ownerVersion();
    }

    /**
     * @notice Gets the ownership version recorded for a specific build
     * @param asset The asset contract address
     * @param buildId The build identifier
     * @return The ownership version recorded when this build was validated
     * @dev Used to track ownership at the time of build validation
     */
    function getLastOwnershipVersion(address asset, uint256 buildId) external view returns (uint256) {
        OpenStoreVaultV0 storage vault = OpenStoreStorageV0.openStoreVault();
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
        OpenStoreVaultV0 storage vault = OpenStoreStorageV0.openStoreVault();
        return vault.tracks[asset][channel];
    }

    /**
     * @notice Gets the latest version code for an asset on a specific distribution track
     * @param asset The asset contract address
     * @param channel The distribution channel/track identifier
     * @return The latest version code on this track
     * @dev Different tracks can have different versions (e.g., stable, beta, alpha)
     */
    function getLastAppVersionAndOwnership(address asset, uint256 channel) external view returns (uint256, uint256) {
        OpenStoreVaultV0 storage vault = OpenStoreStorageV0.openStoreVault();
        uint256 versionCode = vault.tracks[asset][channel];
        uint256 ownership = vault.builds[asset][versionCode];
        return (versionCode, ownership);
    }

    /**
     * @notice Sets the visibility status of an asset in the store
     * @param asset The asset contract address
     * @param isVisible True to make visible, false to hide
     * @dev Controls whether the asset appears in public listings
     */
    function setAssetVisibility(address asset, bool isVisible) external {
        if (msg.sender != PluginOwnable(asset).owner()) {
            revert OpenStoreError(ERROR_NOT_TARGET_OWNER);
        }

        OpenStoreVaultV0 storage vault = OpenStoreStorageV0.openStoreVault();
        vault.visibility[asset] = isVisible;

        emit AppVisibilityChanged(asset, isVisible);
    }

    /////////////////////////////////
    // Request Management
    /////////////////////////////////

    /**
     * @return The next request ID user should create
     */
    function nextRequestIdToCreate() external view returns (uint256) {
        address sender = msg.sender;
        OpenStoreStateV0 storage state = OpenStoreStorageV0.openStoreState();
        return state.nextRequestIdToCreate;
    }

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
     * @notice Creates a new validation request and sets its voting deadline
     * @param sender The request sender (must be target owner)
     * @param msgValue The amount sent with the request (must be >= validationRequestAmount)
     * @param reqType The type of validation request (1 = android_build)
     * @param target The target contract address
     * @param data Encoded request data
     */
    function _addValidationRequest(
        address sender,
        uint256 msgValue,
        uint256 reqType,
        address target,
        bytes memory data
    ) private {
        OpenStoreConfigV0 storage cfg = OpenStoreStorageV0.openStoreConfig();
        bytes memory callData = abi.encodeCall(
            IOpenStoreRequestHandler.onAddValidationRequest,
            (sender, msgValue, reqType, target, data)
        );

        bytes memory result = Address.functionDelegateCall(cfg.requestHandler, callData);

        emit NewRequest(target, result.toUint256(0), reqType, data);
    }
}
