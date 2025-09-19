// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {VersionableOwner} from "../interfaces/VersionableOwner.sol";
import {Trustable} from "../multicall/Trustable.sol";
import {Plugin} from "../plugin/Plugin.sol";
import {PluginOwnable} from "../plugin/PluginOwnable.sol";

/**
 * @dev Storage structure for the AppOwnerPluginV1
 * @param versions Array of ownership versions, each containing domain and proof data
 */
struct AppOwnerPluginV1State {
    AppOwnerPluginV1Version[] versions;
}

/**
 * @dev Represents a single version of app ownership verification
 * @param domain The domain associated with this ownership proof
 * @param fingerprints Array of certificate fingerprints for verification
 * @param proofs Array of cryptographic proofs for ownership
 */
struct AppOwnerPluginV1Version {
    string domain;
    bytes32[] fingerprints;
    bytes[] proofs;
}

/**
 * @title AppOwnerPluginV1
 * @dev Plugin that manages application ownership verification through domain and cryptographic proofs
 * @notice Handles setting and retrieving app ownership information with versioning support
 */
contract AppOwnerPluginV1 is Plugin, VersionableOwner {

    /// @dev Custom error for app owner plugin failures
    /// @param code Error code indicating the specific failure type
    error AppOwnerPluginError(uint32 code);
    uint32 constant private PROOF_EMPTY = 1;
    uint32 constant private FINGERPRINT_PROOF_MISMATCH = 2;

    bytes32 internal constant APP_OWNER_V1 = keccak256("openstore.plugin.storage.AppOwnerPlugin.v1");

    /**
     * @dev Returns the storage reference for this plugin's data
     * @return ds Storage reference to the plugin data
     */
    function state() internal pure returns (AppOwnerPluginV1State storage ds) {
        bytes32 storagePosition = APP_OWNER_V1;
        assembly {
            ds.slot := storagePosition
        }
        return ds;
    }

    /**
     * @dev Sets app ownership information (owner only)
     * @param _domain The domain associated with this ownership
     * @param _fingerprints Array of certificate fingerprints
     * @param _proofs Array of cryptographic proofs
     */
    function setAppOwner(
        string calldata _domain,
        bytes32[] calldata _fingerprints,
        bytes[] calldata _proofs
    ) public onlyOwner {
        _setAppOwner(_domain, _fingerprints, _proofs);
    }

    /**
     * @dev Sets app ownership information via multicall
     * @param sender The address initiating the multicall
     * @param _domain The domain associated with this ownership
     * @param _fingerprints Array of certificate fingerprints
     * @param _proofs Array of cryptographic proofs
     */
    function setAppOwner(
        address sender,
        string calldata _domain,
        bytes32[] calldata _fingerprints,
        bytes[] calldata _proofs
    ) external onlyMulticall {
        _checkOwner(sender);
        _setAppOwner(_domain, _fingerprints, _proofs);
    }

    /**
     * @dev Internal function to set app ownership with validation
     * @param _domain The domain associated with this ownership
     * @param _fingerprints Array of certificate fingerprints
     * @param _proofs Array of cryptographic proofs
     */
    function _setAppOwner(
        string calldata _domain,
        bytes32[] calldata _fingerprints,
        bytes[] calldata _proofs
    ) private {
        if (_proofs.length == 0) {
            revert AppOwnerPluginError(PROOF_EMPTY);
        }

        if (_fingerprints.length != _proofs.length) {
            revert AppOwnerPluginError(FINGERPRINT_PROOF_MISMATCH);
        }

        AppOwnerPluginV1State storage data = state();
        data.versions.push(AppOwnerPluginV1Version({
            domain: _domain,
            fingerprints: _fingerprints,
            proofs: _proofs
        }));
    }

    /**
     * @dev Returns the domain from the latest ownership version
     * @return The domain string, or empty string if no versions exist
     */
    function domain() external view returns (string memory) {
        AppOwnerPluginV1State storage data = state();

        if (data.versions.length == 0) {
            return "";
        }

        return data.versions[data.versions.length - 1].domain;
    }

    /**
     * @dev Returns the domain from a specific ownership version
     * @param _version The version number (1-indexed)
     * @return The domain string for the specified version
     */
    function domain(uint256 _version) external view returns (string memory) {
        return state().versions[_version - 1].domain;
    }

    /**
     * @dev Returns the complete ownership data from the latest version
     * @return The ownership version data including domain, fingerprints, and proofs
     */
    function getState() external view returns (AppOwnerPluginV1Version memory) {
        AppOwnerPluginV1State storage data = state();

        if (data.versions.length == 0) {
            AppOwnerPluginV1Version memory version;
            return version;
        }

        return data.versions[data.versions.length - 1];
    }

    /**
     * @dev Returns the complete ownership data from a specific version
     * @param _version The version number (1-indexed)
     * @return The ownership version data for the specified version
     */
    function getState(uint256 _version) external view returns (AppOwnerPluginV1Version memory) {
        return state().versions[_version - 1];
    }

    /**
     * @dev Returns the total number of ownership versions
     * @return The number of ownership versions that have been set
     */
    function ownerVersion() external view override returns (uint256) {
        return state().versions.length;
    }
}