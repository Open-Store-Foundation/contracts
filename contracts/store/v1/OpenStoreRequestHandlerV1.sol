// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "../../plugin/delegate/PluginDelegatedOwner.sol";
import "./OpenStore.sol";
import "./OpenStoreStorage.sol";
import {BytesParser} from "../../libs/BytesParser.sol";
import {IAssetlinksOracle} from "../../oracle/AssetlinksOracle.sol";
import {IOpenStoreRequestHandler} from "./IOpenStoreRequestHandler.sol";
import {OpenStoreStorage} from "./OpenStoreStorage.sol";
import {PluginOwnable} from "../../plugin/PluginOwnable.sol";

/**
 * @title OpenStoreRequestHandlerV1
 * @dev Handles validation requests for the OpenStore system
 * @notice Processes build validation requests and manages the validation lifecycle
 */
contract OpenStoreRequestHandlerV1 is IOpenStoreRequestHandler {
    
    using BytesParser for bytes;

    /// @dev Custom error for request handler failures
    /// @param code Error code indicating the specific failure type
    error OpenStoreError(uint16 code);
    uint16 private constant ERROR_REQUESTS_SUSPENDED = 15;
    uint16 private constant ERROR_INCORRECT_VALIDATION_FEE = 16;
    uint16 private constant ERROR_NOT_TARGET_OWNER = 17;
    uint16 private constant ERROR_BUILD_ALREADY_VERIFIED = 18;
    uint16 private constant ERROR_OWNER_NOT_VERIFIED = 19;
    uint16 private constant ERROR_BUILD_VERSION_DOWNGRADED = 41;
    uint16 private constant ERROR_BUILD_VERSION_ZERO = 42;
    uint16 private constant ERROR_UNKNOWN_REQUEST_TYPE = 43;

    /// @dev Status codes for validation results
    uint256 constant public STATUS_UNAVAILABLE = 0;  // Request could not be processed
    uint256 constant public STATUS_SUCCESS = 1;      // Validation successful
    uint256 constant public STATUS_RESERVED = 2;     // Reserved for future use
    uint256 constant public STATUS_ERROR = 3;        // Validation failed with error

    /**
     * @dev Processes a new validation request
     * @param sender The address that initiated the request
     * @param msgValue The amount of ETH sent with the request
     * @param reqType The type of validation (1 = build validation)
     * @param target The app contract being validated
     * @param data Encoded validation data (versionCode, ownerVersion, trackId for builds)
     * @return The assigned request ID
     */
    function onAddValidationRequest(
        address sender,
        uint256 msgValue,
        uint256 reqType,
        address target,
        bytes calldata data
    ) external payable returns (uint256) {
        OpenStoreConfig storage config = OpenStoreStorage.openStoreConfig();
        if (config.isRequestsSuspended) {
            revert OpenStoreError(ERROR_REQUESTS_SUSPENDED);
        }

        if (msgValue < config.validationRequestAmount) {
            revert OpenStoreError(ERROR_INCORRECT_VALIDATION_FEE);
        }

        if (reqType == 1) {
            if (sender != PluginDelegatedOwner(target).delegateOwner()) {
                revert OpenStoreError(ERROR_NOT_TARGET_OWNER);
            }

            OpenStoreVault storage vault = OpenStoreStorage.openStoreVault();
            uint256 _versionCode = data.toUint256(0);
            uint256 _ownerVersion = data.toUint256(32);
            uint256 _trackId = data.toUint256(64);
            if (_versionCode <= 0) {
                revert OpenStoreError(ERROR_BUILD_VERSION_ZERO);
            }

            if (vault.builds[target][_versionCode] != 0) {
                revert OpenStoreError(ERROR_BUILD_ALREADY_VERIFIED);
            }
            
            if (vault.tracks[target][_trackId] > _versionCode) {
                revert OpenStoreError(ERROR_BUILD_VERSION_DOWNGRADED);
            }

            if (_ownerVersion > 0) {
                uint256 _verifiedVersionId = IAssetlinksOracle(config.oracle)
                    .getLastVerifiedAssetVersion(target);

                if (_ownerVersion != _verifiedVersionId) {
                    revert OpenStoreError(ERROR_OWNER_NOT_VERIFIED);
                }
            }
        } else {
            revert OpenStoreError(ERROR_UNKNOWN_REQUEST_TYPE);
        }

        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        uint256 nextRequestId = state.nextRequestId;
        uint256 nextFinalRequestId = state.nextFinalRequestId;
        if (nextRequestId == nextFinalRequestId) {
            state.nextProposalTimestampFrom = block.timestamp;
        }

        state.requests[nextRequestId] = RequestInfo({
            reqType: reqType,
            target: target,
            data: data
        });

        state.nextRequestId += 1;

        return nextRequestId;
    }

    /**
     * @dev Processes completed validation requests and updates the vault
     * @param result Bitmask indicating success/failure of each request
     * @param count Number of requests being processed
     * @param fromRequestId Starting request ID in the batch
     * @notice Only successful requests (STATUS_SUCCESS) are processed
     */
    function onRemoveValidationRequests(
        uint256 result,
        uint256 count,
        uint256 fromRequestId
    ) external payable {
        OpenStoreState storage state = OpenStoreStorage.openStoreState();
        OpenStoreVault storage vault = OpenStoreStorage.openStoreVault();

        for (uint256 i = 0; i < count; i++) {
            uint256 status = (result >> (i * 2)) & 3; // 3 - 0b11
            if (status != STATUS_SUCCESS) {
                return;
            }

            uint256 requestId = fromRequestId + i;
            RequestInfo memory req = state.requests[requestId];

            if (req.reqType == 1) {
                uint256 _versionCode = req.data.toUint256(0);
                uint256 _ownerVersion = req.data.toUint256(32);
                vault.builds[req.target][_versionCode] = _ownerVersion;

                uint256 _trackId = req.data.toUint256(64);
                uint256 _existingVersion = vault.tracks[req.target][_trackId];
                if (_versionCode > 0 && _trackId > 0 && _versionCode > _existingVersion) {
                    vault.tracks[req.target][_trackId] = _versionCode;
                }
            }
        }
    }
} 