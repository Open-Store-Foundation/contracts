// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {Trustable} from "../multicall/Trustable.sol";
import {PluginOwnable} from "./PluginOwnable.sol";

/**
 * @title Plugin
 * @dev Abstract base contract for all plugins in the system
 * @notice Provides the foundation for plugin contracts with ownership and multicall capabilities
 */
abstract contract Plugin is PluginOwnable, Trustable {
    /**
     * @dev Called when the plugin is added to a manager contract
     * @param data Initialization data passed during plugin installation
     * @notice Override this function to implement plugin-specific initialization logic
     */
    function initialize(bytes memory data) external virtual payable {}
    
    /**
     * @dev Called when the plugin is removed from a manager contract
     * @param data Cleanup data passed during plugin removal
     * @notice Override this function to implement plugin-specific cleanup logic
     */
    function drain(bytes memory data) external virtual payable {}
}
