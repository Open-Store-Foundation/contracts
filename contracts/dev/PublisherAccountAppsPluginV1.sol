// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {AppAsset} from "../app/AppAsset.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IContractStorage} from "../common/ContractStorage.sol";
import {Plugin} from "../plugin/Plugin.sol";
import {PublisherFacetStorageV1} from "./PublisherFacetStorageV1.sol";

/**
 * @dev Storage structure for the PublisherAccountAppsPluginV1
 * @param appsHashes Mapping from app ID hash to deployed app contract address
 */
struct PublisherAccountAppsPluginV1State {
    mapping(bytes32 => address) appsHashes; // keccak(app.id) -> address
}

/**
 * @title PublisherAccountAppsPluginV1
 * @dev Plugin that enables publisher accounts to create and manage application contracts
 * @notice Provides functionality for creating apps with deterministic addresses using CREATE2
 */
contract PublisherAccountAppsPluginV1 is Plugin {

    /// @dev Custom error for publisher account apps plugin failures
    /// @param code Error code indicating the specific failure type
    error PublisherAccountAppsPluginError(uint32 code);

    // Error codes
    uint32 private constant APP_ALREADY_EXISTS = 1;

    // Plugins
    bytes32 public constant APP_PLUGINS = keccak256("openstore.plugins.default.AppAsset.v1");
    bytes32 private constant PUBLISHER_ACCOUNT_APPS_V1 = keccak256("openstore.plugin.storage.PublisherAccountAppsPlugin.v1");

    /// @dev Emitted when a new app is created
    /// @param appAddress The address of the created app contract
    /// @param id The unique identifier of the app
    /// @param name The display name of the app
    event AppCreated(address indexed appAddress, string id, string name);

    

    address private immutable pluginStorage;

    /**
     * @dev Initializes the plugin with contract storage address
     * @param _contracts Address of the contract storage for default plugin configurations
     */
    constructor(address _contracts) {
        pluginStorage = _contracts;
    }
    
    /**
     * @dev Returns the storage reference for this plugin's data
     * @return ds Storage reference to the plugin data
     */
    function state() private pure returns (PublisherAccountAppsPluginV1State storage ds) {
        bytes32 storagePosition = PUBLISHER_ACCOUNT_APPS_V1;

        assembly {
            ds.slot := storagePosition
        }

        return ds;
    }

    /**
     * @dev Computes the deterministic address where an app will be deployed
     * @param _id The unique identifier for the app
     * @param _name The display name of the app
     * @param _description The description of the app
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier
     * @return appAddress The computed CREATE2 deployment address for the app
     */
    /**
     * @dev Computes deterministic app address using default plugin set from contract storage
     * @param _id App package identifier
     * @param _name App display name
     * @param _description App description
     * @param _protocolId Protocol identifier
     * @param _platformId Platform identifier
     * @param _categoryId Category identifier
     * @return appAddress Predicted address of the app contract
     */
    function computeAppAddress(
        string memory _id,
        string memory _name,
        string memory _description,

        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId
    ) external view returns (address) {
        bytes32 idHash = keccak256(bytes(_id));
        bytes memory bytecode = _getBytecode(
            _id, _name, _description,
            _protocolId, _platformId, _categoryId
        );
        return Create2.computeAddress(idHash, keccak256(bytecode));
    }

    /**
     * @dev Computes deterministic app address using caller-provided plugin configuration
     * @param _id App package identifier
     * @param _name App display name
     * @param _description App description
     * @param _protocolId Protocol identifier
     * @param _platformId Platform identifier
     * @param _categoryId Category identifier
     * @param _plugins Plugin implementation addresses
     * @param _data Initialization calldata per plugin
     * @param _selectors Function selectors per plugin
     * @return appAddress Predicted address of the app contract
     */
    function computeAppAddress(
        string memory _id,
        string memory _name,
        string memory _description,
        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId,
        address[] memory _plugins,
        bytes[] memory _data,
        bytes4[][] memory _selectors
    ) external view returns (address) {
        bytes32 idHash = keccak256(bytes(_id));
        bytes memory bytecode = _getBytecode(
            _id, _name, _description,
            _protocolId, _platformId, _categoryId,
            _plugins, _data, _selectors
        );
        return Create2.computeAddress(idHash, keccak256(bytecode));
    }

    /**
     * @dev Creates a new app contract (owner only)
     * @param _id The unique identifier for the app
     * @param _name The display name of the app
     * @param _description The description of the app
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier
     */
    /**
     * @dev Creates an app using default plugins (owner only)
     */
    function createApp(
        string memory _id,
        string memory _name,
        string memory _description,

        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId
    ) external onlyOwner {
        _createApp(_id, _name, _description, _protocolId, _platformId, _categoryId);
    }

    /**
     * @dev Creates an app using caller-provided plugins (owner only)
     */
    function createApp(
        string memory _id,
        string memory _name,
        string memory _description,
        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId,
        address[] memory _plugins,
        bytes[] memory _data,
        bytes4[][] memory _selectors
    ) external onlyOwner {
        _createApp(
            _id, _name, _description,
            _protocolId, _platformId, _categoryId,
            _plugins, _data, _selectors
        );
    }

    /**
     * @dev Creates a new app contract via multicall
     * @param sender The address initiating the multicall
     * @param _id The unique identifier for the app
     * @param _name The display name of the app
     * @param _description The description of the app
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier
     */
    /**
     * @dev Creates an app using default plugins via multicall
     * @param sender Publisher account expected to be the owner
     */
    function createApp(
        address sender,
        string memory _id,
        string memory _name,
        string memory _description,

        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId
    ) external onlyMulticall {
        _checkOwner(sender);
        _createApp(_id, _name, _description, _protocolId, _platformId, _categoryId);
    }

    /**
     * @dev Creates an app using caller-provided plugins via multicall
     * @param sender Publisher account expected to be the owner
     */
    function createApp(
        address sender,
        string memory _id,
        string memory _name,
        string memory _description,
        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId,
        address[] memory _plugins,
        bytes[] memory _data,
        bytes4[][] memory _selectors
    ) external onlyMulticall {
        _checkOwner(sender);
        _createApp(
            _id, _name, _description,
            _protocolId, _platformId, _categoryId,
            _plugins, _data, _selectors
        );
    }

    /**
     * @dev Internal function to create an app with validation
     * @param _id The unique identifier for the app
     * @param _name The display name of the app
     * @param _description The description of the app
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier
     */
    /**
     * @dev Internal: creates app using default plugins
     */
    function _createApp(
        string memory _id,
        string memory _name,
        string memory _description,

        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId
    ) private {
        (address[] memory addrs, bytes[] memory data, bytes4[][] memory selectors) = IContractStorage(pluginStorage).getDefaultPluginsById(APP_PLUGINS);
        _createApp(
            _id,
            _name,
            _description,
            _protocolId,
            _platformId,
            _categoryId,
            addrs,
            data,
            selectors
        );
    }

    /**
     * @dev Internal: creates app using provided plugin configuration
     */
    function _createApp(
        string memory _id,
        string memory _name,
        string memory _description,
        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId,
        address[] memory _plugins,
        bytes[] memory _data,
        bytes4[][] memory _selectors
    ) private {
        bytes32 idHash = keccak256(bytes(_id));
        PublisherAccountAppsPluginV1State storage s = state();
        if (s.appsHashes[idHash] != address(0)) {
            revert PublisherAccountAppsPluginError(APP_ALREADY_EXISTS);
        }

        bytes memory bytecode = _getBytecode(
            _id, _name, _description,
            _protocolId, _platformId, _categoryId,
            _plugins, _data, _selectors
        );
        address appAddress = Create2.deploy(0, idHash, bytecode);
        s.appsHashes[idHash] = appAddress;
        emit AppCreated(appAddress, _id, _name);
    }

    /**
     * @dev Generates the bytecode for deploying an app contract
     * @param _id The unique identifier for the app
     * @param _name The display name of the app
     * @param _description The description of the app
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier
     * @return bytecode The complete constructor-encoded bytecode for app deployment
     */
    /**
     * @dev Internal: builds creation bytecode using default plugins
     */
    function _getBytecode(
        string memory _id,
        string memory _name,
        string memory _description,
    
        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId
    ) private view returns (bytes memory) {
        IContractStorage store = IContractStorage(pluginStorage);
        (address[] memory addrs, bytes[] memory data, bytes4[][] memory selectors) = store.getDefaultPluginsById(APP_PLUGINS);
        return _getBytecode(
            _id,
            _name,
            _description,
            _protocolId,
            _platformId,
            _categoryId,
            addrs,
            data,
            selectors
        );
    }

    /**
     * @dev Internal: builds creation bytecode using provided plugin configuration
     */
    function _getBytecode(
        string memory _id,
        string memory _name,
        string memory _description,
        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId,
        address[] memory _plugins,
        bytes[] memory _data,
        bytes4[][] memory _selectors
    ) private view returns (bytes memory) {
        bytes memory constructorArgs = abi.encode(
            address(this),
            _id,
            _name,
            _description,

            _protocolId,
            _platformId,
            _categoryId,

            _plugins,
            _data,
            _selectors
        );
        return abi.encodePacked(type(AppAsset).creationCode, constructorArgs);
    }

    /**
     * @dev Retrieves the address of an app by its ID
     * @param idHash The keccak hash of unique identifier of the app
     */
    function getAppById(bytes32 idHash) external view returns (address) {
        PublisherAccountAppsPluginV1State storage state = state();
        return state.appsHashes[idHash];
    }
}
