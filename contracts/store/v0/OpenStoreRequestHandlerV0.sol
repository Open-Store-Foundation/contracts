// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "../../plugin/delegate/PluginDelegatedOwner.sol";
import "../IOpenStoreRequestHandler.sol";
import "./OpenStoreStorageV0.sol";
import {BytesParser} from "../../libs/BytesParser.sol";
import {IAssetlinksOracle} from "../../oracle/AssetlinksOracle.sol";
import {PluginOwnable} from "../../plugin/PluginOwnable.sol";

/**
 * @title OpenStoreRequestHandlerV1
 * @dev Handles validation requests for the OpenStore system
 * @notice Processes build validation requests and manages the validation lifecycle
 */
contract OpenStoreRequestHandlerV0 is IOpenStoreRequestHandler {
    
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
        OpenStoreConfigV0 storage config = OpenStoreStorageV0.openStoreConfig();
        if (config.isRequestsSuspended) {
            revert OpenStoreError(ERROR_REQUESTS_SUSPENDED);
        }

        OpenStoreStateV0 storage state = OpenStoreStorageV0.openStoreState();
        if (sender != PluginDelegatedOwner(target).delegateOwner()) {
            revert OpenStoreError(ERROR_NOT_TARGET_OWNER);
        }

        if (reqType == 1) {
            uint256 _versionCode = data.toUint256(0);
            uint256 _ownerVersion = data.toUint256(32);
            uint256 _trackId = data.toUint256(64);

            if (_versionCode <= 0) {
                revert OpenStoreError(ERROR_BUILD_VERSION_ZERO);
            }

            OpenStoreVaultV0 storage vault = OpenStoreStorageV0.openStoreVault();

            if (_ownerVersion > 0) {
                uint256 _verifiedVersionId = IAssetlinksOracle(config.oracle)
                    .getLastVerifiedAssetVersion(target);

                if (_ownerVersion != _verifiedVersionId) {
                    revert OpenStoreError(ERROR_OWNER_NOT_VERIFIED);
                }

                vault.builds[target][_versionCode] = _ownerVersion;
            }

            vault.builds[target][_trackId] = _versionCode;
        } else {
            revert OpenStoreError(ERROR_UNKNOWN_REQUEST_TYPE);
        }

        uint256 requestId = state.nextRequestIdToCreate;
        state.nextRequestIdToCreate = requestId + 1;

        return requestId;
    }

    function onRemoveValidationRequests(
        uint256 result,
        uint256 count,
        uint256 fromRequestId
    ) external payable {}
}
