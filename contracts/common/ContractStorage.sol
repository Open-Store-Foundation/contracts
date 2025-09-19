// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title IContractStorage
 * @dev Interface for managing default plugin configurations by identifier
 */
interface IContractStorage {
    /**
     * @dev Retrieves default plugin configuration for a given identifier
     * @param id The identifier to look up
     * @return plugins Array of plugin contract addresses
     * @return data Array of initialization data for each plugin
     * @return selectors Array of function selectors for each plugin
     */
    function getDefaultPluginsById(bytes32 id) external view returns (address[] memory, bytes[] memory, bytes4[][] memory);
    
    /**
     * @dev Sets default plugin configuration for a given identifier
     * @param id The identifier to configure
     * @param plugins Array of plugin contract addresses
     * @param data Array of initialization data for each plugin
     * @param selectors Array of function selectors for each plugin
     */
    function setDefaultPluginsForId(bytes32 id, address[] calldata plugins, bytes[] calldata data, bytes4[][] calldata selectors) external;
}

/**
 * @title ContractStorage
 * @dev Storage contract for managing default plugin configurations by identifier
 * @notice Allows storing and retrieving default plugin setups for different contract types
 */
contract ContractStorage is Ownable, IContractStorage {

    /**
     * @dev Configuration structure for storing plugin information
     * @param plugins Array of plugin contract addresses
     * @param data Array of initialization data for each plugin
     * @param selectors Array of function selectors for each plugin
     */
    struct PluginConfig {
        address[] plugins;
        bytes[] data;
        bytes4[][] selectors;
    }

    mapping(bytes32 => PluginConfig) private pluginConfigs;

    /**
     * @dev Initializes the contract with the deployer as owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Sets the default plugin configuration for a specific identifier
     * @param id The identifier for this configuration
     * @param plugins Array of plugin contract addresses
     * @param data Array of initialization data for each plugin
     * @param selectors Array of function selectors for each plugin
     * @notice Only the contract owner can set configurations
     */
    function setDefaultPluginsForId(
        bytes32 id,
        address[] calldata plugins,
        bytes[] calldata data,
        bytes4[][] calldata selectors
    ) external onlyOwner {
        require(plugins.length == data.length && plugins.length == selectors.length, "Invalid array lengths");
        pluginConfigs[id] = PluginConfig(plugins, data, selectors);
    }

    /**
     * @dev Retrieves the default plugin configuration for a specific identifier
     * @param id The identifier to look up
     * @return plugins Array of plugin contract addresses
     * @return data Array of initialization data for each plugin  
     * @return selectors Array of function selectors for each plugin
     */
    function getDefaultPluginsById(
        bytes32 id
    ) external view returns (
        address[] memory,
        bytes[] memory,
        bytes4[][] memory
    ) {
        PluginConfig storage config = pluginConfigs[id];
        return (config.plugins, config.data, config.selectors);
    }
}
