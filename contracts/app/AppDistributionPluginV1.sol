// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {Trustable} from "../multicall/Trustable.sol";
import {PluginOwnable} from "../plugin/PluginOwnable.sol";
import {DelegatedPlugin} from "../plugin/delegate/DelegatedPlugin.sol";

/**
 * @dev Storage structure for the AppDistributionPluginV1
 * @param typeId The type identifier for the distribution method
 * @param sources Array of distribution source data
 */
struct AppDistributionPluginV1Data {
    uint16 typeId;
    bytes[] sources;
}

/**
 * @title AppDistributionPluginV1
 * @dev Plugin that manages application distribution sources and methods
 * @notice Handles setting and retrieving distribution information for applications
 */
contract AppDistributionPluginV1 is DelegatedPlugin {

    bytes32 internal constant APP_DISTRIBUTION_V1 = keccak256("openstore.plugin.storage.AppDistributionPlugin.v1");

    event DistributionListChanged();

    /**
     * @dev Returns the storage reference for this plugin's data
     * @return ds Storage reference to the plugin data
     */
    function state() internal pure returns (AppDistributionPluginV1Data storage ds) {
        bytes32 storagePosition = APP_DISTRIBUTION_V1;
        assembly {
            ds.slot := storagePosition
        }
        return ds;
    }

    /**
     * @dev Sets the distribution configuration (owner only)
     * @param _typeId The distribution type identifier
     * @param _sources Array of distribution source data
     */
    function setDistribution(uint16 _typeId, bytes[] calldata _sources) external onlyDelegateOwner {
        _setDistribution(_typeId, _sources);
    }

    /**
     * @dev Sets the distribution configuration via multicall
     * @param sender The address initiating the multicall
     * @param _typeId The distribution type identifier
     * @param _sources Array of distribution source data
     */
    function setDistribution(address sender, uint16 _typeId, bytes[] calldata _sources) external onlyMulticall {
        _checkDelegateOwner(sender);
        _setDistribution(_typeId, _sources);
    }

    /**
     * @dev Internal function to set distribution configuration
     * @param _typeId The distribution type identifier
     * @param _sources Array of distribution source data
     */
    function _setDistribution(uint16 _typeId, bytes[] calldata _sources) private {
        AppDistributionPluginV1Data storage data = state();
        data.typeId = _typeId;
        data.sources = _sources;

        emit DistributionListChanged();
    }

    /**
     * @dev Retrieves a specific distribution source by index
     * @param _id The index of the distribution source
     * @return The distribution source data
     */
    function getSource(uint256 _id) external view returns (bytes memory) {
        return state().sources[_id];
    }

    /**
     * @dev Retrieves the complete distribution configuration
     * @return The complete distribution data including type and sources
     */
    function getDistribution() external view returns (AppDistributionPluginV1Data memory) {
        return state();
    }
}
