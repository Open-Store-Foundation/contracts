// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "./PluginOwnable.sol";
import {ITrustedCall} from "../multicall/ITrustedCall.sol";
import {PluginOwnable} from "./PluginOwnable.sol";
import {Trustable} from "../multicall/Trustable.sol";
import {TrustedCalldata} from "../multicall/TrustedCalldata.sol";

/**
 * @title PluginManager
 * @dev Abstract contract for managing plugin functionality and delegation
 * @notice Provides a plugin architecture where functions can be delegated to plugin contracts
 */
/**
 * @title PluginManager
 * @dev Abstract base providing registration and delegation of plugin contracts
 * @notice Routes function calls to plugins by selector and supports trusted multicall execution
 */
abstract contract PluginManager is PluginOwner, Trustable, ITrustedCall {

    mapping(bytes4 => address) public selectors;
    mapping(address => bool) public plugins;

    /**
     * @dev Initializes the plugin manager with an initial owner
     * @param initialOwner The address that will own this plugin manager
     */
    constructor(address initialOwner) PluginOwner(initialOwner) {}

    /**
     * @dev Adds a new plugin to the manager (owner only)
     * @param _plugin The address of the plugin contract
     * @param data Initialization data for the plugin
     * @param _selectors Array of function selectors that this plugin will handle
     */
    function addPlugin(address _plugin, bytes memory data, bytes4[] memory _selectors) external onlyOwner {
        _addPlugin(_plugin, data, _selectors);
    }

    /**
     * @dev Internal function to add a plugin with initialization and selector registration
     * @param _plugin The address of the plugin contract
     * @param data Initialization data for the plugin
     * @param _selectors Array of function selectors that this plugin will handle
     */
    function _addPlugin(address _plugin, bytes memory data, bytes4[] memory _selectors) internal {
        require(!plugins[_plugin], "You already have this plugin!");

        _pluginLifecycleCall(
            _plugin,
            abi.encodeWithSignature("initialize(bytes)", data)
        );

        for (uint256 i = 0; i < _selectors.length; i++) {
            selectors[_selectors[i]] = _plugin;
        }

        plugins[_plugin] = true;
    }

    /**
     * @dev Removes a plugin from the manager (owner only)
     * @param _plugin The address of the plugin contract to remove
     * @param data Cleanup data for the plugin
     * @param _selectors Array of function selectors to unregister
     */
    function removePlugin(address _plugin, bytes memory data, bytes4[] memory _selectors) external onlyOwner  {
        require(plugins[_plugin], "Contract don't have such plugin yet!");

        _pluginLifecycleCall(
            _plugin,
            abi.encodeWithSignature("drain(bytes)", data)
        );

        for (uint256 i = 0; i < _selectors.length; i++) {
            delete selectors[_selectors[i]];
        }

        delete plugins[_plugin];
    }

    /**
     * @dev Checks if a plugin is registered with this manager
     * @param _plugin The address of the plugin to check
     * @return True if the plugin is registered, false otherwise
     */
    function hasPlugin(address _plugin) public view returns (bool) {
        return plugins[_plugin];
    }

    /**
     * @dev Executes a trusted call via multicall, to either a plugin or the manager
     * @param call The trusted call payload
     */
    function trustedCall(TrustedCalldata memory call) onlyMulticall external payable virtual override {
        if (call.plugin != address(0)) {
            require(plugins[call.plugin], "Can't find plugin for multicall!");

            _pluginRawCall(
                call.plugin,
                call.data
            );
        } else {
            _pluginRawCall(
                call.manager,
                call.data
            );
        }
    }

    /**
     * @dev Delegates unknown calls to registered plugins based on function selector
     * @notice Automatically routes external calls to the appropriate plugin if registered
     */
    fallback() external payable {
        address plugin = selectors[msg.sig];
        require(plugin != address(0), "Function does not exist!");

        _pluginRawCall(plugin, msg.data);
    }

    /**
     * @dev Internal function for making lifecycle calls (initialize/drain) to plugins
     * @param plugin The plugin address to call
     * @param data The encoded function call data
     */
    function _pluginLifecycleCall(address plugin, bytes memory data) private {
        (bool success, bytes memory result) = plugin.delegatecall(data);

        if (!success) {
            require(result.length > 0, "Plugin lifecycle call failed without a reason!");

            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * @dev Internal function for making raw delegatecalls to plugins with return data forwarding
     * @param plugin The plugin address to call
     * @param data The encoded function call data
     */
    function _pluginRawCall(address plugin, bytes memory data) private {
        (bool success, bytes memory result) = plugin.delegatecall(data);

        if (!success) {
            require(result.length > 0, "Plugin call failed without a reason!");

            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        assembly {
            return (add(result, 32), mload(result))
        }
    }
}
