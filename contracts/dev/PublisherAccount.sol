// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "./PublisherFacetStorageV1.sol";
import {Named} from "../interfaces/Named.sol";
import {PluginManager} from "../plugin/PluginManager.sol";
import {PublisherAccountStorageData, PublisherFacetStorageV1} from "./PublisherFacetStorageV1.sol";
import {StringVerifier} from "../libs/StringVerifier.sol";

/**
 * @title PublisherAccount
 * @dev Core publisher account contract that manages developer/publisher information and plugins
 * @notice Represents a publisher account in the OpenStore ecosystem with plugin-based extensibility
 */
contract PublisherAccount is PluginManager, Named {

    using StringVerifier for string;

    /// @dev Custom error for publisher account related failures
    /// @param code Error code indicating the specific failure type
    error PublisherAccountError(uint32 code);

    // Error Codes
    uint32 constant private NAME_LENGTH = 1;
    uint32 constant private PLUGIN_SELECTOR_LENGTH_MISMATCH = 2;

    // Const
    uint256 constant private MIN_LENGTH = 3;
    uint256 constant private MAX_NAME_LENGTH = 50;

    /**
     * @dev Initializes a new publisher account with plugins
     * @param _owner The address that will own this publisher account
     * @param _name The name of the publisher account
     * @param _plugins Array of plugin contract addresses to install
     * @param _data Array of initialization data for each plugin
     * @param _selectors Array of function selectors for each plugin
     */
    constructor(
        address _owner,
        string memory _name,

        address[] memory _plugins,
        bytes[] memory _data,
        bytes4[][] memory _selectors
    ) PluginManager(_owner) {
        bytes memory nameData = bytes(_name);
        if (!_name.isValidLength(MIN_LENGTH, MAX_NAME_LENGTH)) {
            revert PublisherAccountError(NAME_LENGTH);
        }

        PublisherAccountStorageData storage data = PublisherFacetStorageV1.common();
        data.name = _name;

        if (_plugins.length != _selectors.length) {
            revert PublisherAccountError(PLUGIN_SELECTOR_LENGTH_MISMATCH);
        }

        for (uint256 i = 0; i < _plugins.length; i++) {
            _addPlugin(_plugins[i], _data[i], _selectors[i]);
        }
    }

    /**
     * @dev Returns the name of this publisher account
     * @return The publisher account name
     */
    function getName() external view returns (string memory) {
        PublisherAccountStorageData storage data = PublisherFacetStorageV1.common();
        return data.name;
    }
}
