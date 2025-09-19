// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {Plugin} from "../plugin/Plugin.sol";

/**
 * @dev Represents a single build/version of an application
 * @param referenceId External reference identifier for this build
 * @param protocolId The protocol this build is associated with
 * @param versionName Human-readable version string (e.g., "1.0.0")
 * @param versionCode Numeric version code for ordering
 * @param checksum Hash checksum for build integrity verification
 */
struct AppBuild {
    bytes referenceId;
    uint16 protocolId;
    string versionName;
    uint256 versionCode;
    bytes32 checksum;
}

/**
 * @dev Storage structure for the AppBuildsPluginV1
 * @param lastVersionCode The highest version code that has been added
 * @param builds Mapping from version code to build information
 */
struct AppBuildsPluginV1Data {
    uint256 lastVersionCode;
    mapping(uint256 => AppBuild) builds;
}

/**
 * @title AppBuildsPluginV1
 * @dev Plugin that manages application builds and versions
 * @notice Handles adding new builds, version tracking, and build retrieval
 */
contract AppBuildsPluginV1 is Plugin {

    /// @dev Custom error for app builds plugin failures
    /// @param code Error code indicating the specific failure type
    error AppBuildsPluginError(uint32 code);

    // Error Codes
    uint32 constant private VERSION_CODE_NEGATIVE = 1;
    uint32 constant private VERSION_CODE_NOT_HIGHER = 2;

    // Const
    bytes32 internal constant APP_BUILD_V1 = keccak256("openstore.plugin.storage.AppBuildsPlugin.v1");

    /**
     * @dev Returns the storage reference for this plugin's data
     * @return ds Storage reference to the plugin data
     */
    function state() internal pure returns (AppBuildsPluginV1Data storage ds) {
        bytes32 storagePosition = APP_BUILD_V1;
        assembly {
            ds.slot := storagePosition
        }
        return ds;
    }

    /**
     * @dev Adds a new build to the application (owner only)
     * @param build The build information to add
     */
    function addBuild(AppBuild calldata build) external onlyOwner {
        _addBuild(build);
    }

    /**
     * @dev Adds a new build via multicall (allows batching with other operations)
     * @param sender The address initiating the multicall
     * @param build The build information to add
     */
    function addBuild(
        address sender,
        AppBuild calldata build
    ) external onlyMulticall {
        _checkOwner(sender);
        _addBuild(build);
    }

    /**
     * @dev Internal function to add a build with validation
     * @param build The build information to add
     */
    function _addBuild(AppBuild calldata build) internal {
        if (build.versionCode <= 0) {
            revert AppBuildsPluginError(VERSION_CODE_NEGATIVE);
        }

        AppBuildsPluginV1Data storage data = state();

        if (data.lastVersionCode >= build.versionCode) {
            revert AppBuildsPluginError(VERSION_CODE_NOT_HIGHER);
        }

        data.builds[build.versionCode] = build;
        data.lastVersionCode = build.versionCode;
    }

    /**
     * @dev Returns the highest version code that has been added
     * @return The last version code
     */
    function getLastVersionCode() external view returns (uint256) {
        return state().lastVersionCode;
    }

    /**
     * @dev Checks if a build exists for the given version code
     * @param versionCode The version code to check
     * @return True if the build exists, false otherwise
     */
    function hasBuild(uint256 versionCode) external view returns (bool) {
        return state().builds[versionCode].versionCode > 0;
    }

    /**
     * @dev Retrieves build information for a specific version code
     * @param versionCode The version code to retrieve
     * @return The build information for the specified version
     */
    function getBuild(uint256 versionCode) external view returns (AppBuild memory) {
        return state().builds[versionCode];
    }
}
