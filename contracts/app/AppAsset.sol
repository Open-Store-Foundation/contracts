// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "../plugin/PluginDelegatedOwner.sol";
import "./AppFacetStorage.sol";
import {AppFacetStorage} from "./AppFacetStorage.sol";
import {PluginManager} from "../plugin/PluginManager.sol";
import {StringVerifier} from "../libs/StringVerifier.sol";
import {Trustable} from "../multicall/Trustable.sol";

/**
 * @title AppAsset
 * @dev Core application asset contract that manages app metadata and plugins
 * @notice This contract handles app information, validation, and plugin management for applications in the OpenStore
 */
contract AppAsset is PluginManager, PluginDelegatedOwner {

    using StringVerifier for string;

    /// @dev Custom error for app-related failures
    /// @param code Error code indicating the specific failure type
    error AppError(uint32 code);

    // Error Codes
    uint32 constant private PACKAGE_NAME_LENGTH = 1;
    uint32 constant private NAME_LENGTH = 2;
    uint32 constant private PLUGIN_SELECTOR_LENGTH_MISMATCH = 3;

    // Const
    uint256 constant private MIN_LENGTH = 3;
    uint256 constant private MAX_NAME_LENGTH = 40;
    uint256 constant private MAX_PACKAGE_LENGTH = 150;

    event AppAssetFullInfoUpdated();
    event AppAssetNameUpdated(string name);
    event AppAssetDescriptionUpdated(bytes content);
    event AppAssetCategoryUpdated(uint16 categoryId);
    event AppAssetPlatformUpdated(uint16 platformId);

    /**
     * @dev Modifier to verify that the app name meets length requirements
     * @param _name The name to validate
     */
    modifier verifyName(string memory _name) {
        if (!_name.isValidLength(MIN_LENGTH, MAX_NAME_LENGTH)) {
            revert AppError(NAME_LENGTH);
        }

        _;
    }

    /**
     * @dev Overrides ownership getter for delegated pattern
     * @notice Resolves multiple inheritance by explicitly calling PluginDelegatedOwner's implementation
     */
    function owner() public view virtual override(PluginOwnable, PluginDelegatedOwner) returns (address) {
       return PluginDelegatedOwner.owner();
    }

    /**
     * @dev Initializes a new app asset with metadata and plugins
     * @param _developer The developer/publisher address that will own this app (PublisherAccount address)
     * @param _id The unique identifier for this app (package name)
     * @param _name The display name of the application
     * @param _description A description of the application
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier for this app
     * @param _plugins Array of plugin contract addresses to install
     * @param _data Array of initialization data for each plugin
     * @param _selectors Array of function selectors for each plugin
     */
    constructor(
        address _developer,

        string memory _id,
        string memory _name,
        bytes memory _description,

        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId,

        address[] memory _plugins,
        bytes[] memory _data,
        bytes4[][] memory _selectors
    ) PluginManager(_developer) verifyName(_name) {
        if (!StringVerifier.isValidLength(_id, MIN_LENGTH, MAX_PACKAGE_LENGTH)) {
            revert AppError(PACKAGE_NAME_LENGTH);
        }

        if (_plugins.length != _selectors.length) {
            revert AppError(PLUGIN_SELECTOR_LENGTH_MISMATCH);
        }

        AppGeneralInfo storage info = AppFacetStorage.general();
        // Immutable
        info.id = _id;
        info.categoryId = _categoryId;

        // Mutable
        info.name = _name;
        info.description = _description;
        info.platformId = _platformId;
        info.protocolId = _protocolId;

        for (uint256 i = 0; i < _plugins.length; i++) {
            _addPlugin(_plugins[i], _data[i], _selectors[i]);
        }
    }

    /**
     * @dev Returns the complete general information about this app
     * @return The AppGeneralInfo struct containing all app metadata
     */
    function getGeneralInfo() public view returns (AppGeneralInfo memory) {
        AppGeneralInfo memory info = AppFacetStorage.general();
        return info;
    }

    /**
     * @dev Returns the display name of this application
     * @return The application name
     */
    function getName() public view returns (string memory) {
        AppGeneralInfo memory info = AppFacetStorage.general();
        return info.name;
    }

    /**
     * @dev Returns the unique identifier (package name) of this application
     * @return The application ID
     */
    function getId() public view returns (string memory) {
        AppGeneralInfo memory info = AppFacetStorage.general();
        return info.id;
    }

    /**
     * @dev Returns the description of this application
     * @return The application description
     */
    function getDescription() public view returns (bytes memory) {
        AppGeneralInfo memory info = AppFacetStorage.general();
        return info.description;
    }

    /**
     * @dev Returns the protocol ID for this application
     * @return The protocol identifier
     */
    function getCategory() public view returns (uint16) {
        AppGeneralInfo memory info = AppFacetStorage.general();
        return info.categoryId;
    }


    /**
     * @dev Returns the protocol ID for this application
     * @return The protocol identifier
     */
    function getProtocol() public view returns (uint16) {
        AppGeneralInfo memory info = AppFacetStorage.general();
        return info.protocolId;
    }

    /**
     * @dev Updates multiple app metadata fields at once
     * @param _name The new display name for the application
     * @param _description The new description for the application
     * @param _categoryId The new category identifier
     */
    function updateGeneralInfo(
        string calldata _name,
        bytes calldata _description,
        uint16 _categoryId
    ) external onlyOwner verifyName(_name) {
        AppGeneralInfo storage info = AppFacetStorage.general();
        info.name = _name;
        info.description = _description;
        info.categoryId = _categoryId;

        emit AppAssetFullInfoUpdated();
    }

    /**
     * @dev Updates the application display name
     * @param _name The new name for the application
     */
    function setName(string calldata _name) external onlyOwner verifyName(_name) {
        AppGeneralInfo storage info = AppFacetStorage.general();
        info.name = _name;

        emit AppAssetNameUpdated(_name);
    }

    /**
     * @dev Updates the application description
     * @param _description The new description for the application
     */
    function setDescription(bytes calldata _description) external onlyOwner {
        AppGeneralInfo storage info = AppFacetStorage.general();
        info.description = _description;

        emit AppAssetDescriptionUpdated(_description);
    }

    /**
     * @dev Updates the application category
     * @param _categoryId The new category identifier
     */
    function setCategoryId(uint16 _categoryId) external onlyOwner {
        AppGeneralInfo storage info = AppFacetStorage.general();
        info.categoryId = _categoryId;

        emit AppAssetCategoryUpdated(_categoryId);
    }

    /**
     * @dev Updates the protocol ID for this application
     * @param _protocolId The new protocol identifier
     */
    function setProtocolId(uint16 _protocolId) external onlyOwner {
        _setProtocolId(_protocolId);
    }

    /**
     * @dev Updates the protocol ID via multicall (allows batching with other operations)
     * @param sender The address initiating the multicall
     * @param _protocolId The new protocol identifier
     */
    function setProtocolId(address sender, uint16 _protocolId) external onlyMulticall {
        _checkMulticall(sender);
        _setProtocolId(_protocolId);
    }

    /**
     * @dev Internal function to update the protocol ID
     * @param _protocolId The protocol identifier to set
     */
    function _setProtocolId(uint16 _protocolId) private {
        AppGeneralInfo storage info = AppFacetStorage.general();
        info.protocolId = _protocolId;

        emit AppAssetPlatformUpdated(_protocolId);
    }
}
