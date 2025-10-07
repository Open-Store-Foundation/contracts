// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "../interfaces/TransferableOwner.sol";
import {AppAsset} from "../app/AppAsset.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IContractStorage} from "../common/ContractStorage.sol";
import {Plugin} from "../plugin/Plugin.sol";
import {PublisherFacetStorageV1} from "./PublisherFacetStorageV1.sol";

/**
 * @dev Storage structure for the PublisherAccountAppsPluginV1
 * @param apps Mapping from app ID hash to deployed app contract address
 * @param pendingTransfers Mapping from app ID hash to approved new owner address
 */
struct PublisherAccountAppsPluginV1State {
    mapping(bytes32 => address) apps;
    mapping(bytes32 => address) pendingTransfers;
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
    uint32 private constant APP_NOT_FOUND = 2;
    uint32 private constant TRANSFER_NOT_APPROVED = 3;

    // Plugins
    bytes32 public constant APP_PLUGINS = keccak256("openstore.plugins.default.AppAsset.v1");
    bytes32 private constant DEV_ACCOUNT_APPS_V1 = keccak256("openstore.plugin.storage.PublisherAccountAppsPlugin.v1");

    /// @dev Emitted when a new app is created
    /// @param appAddress The address of the created app contract
    /// @param id The unique identifier of the app
    /// @param name The display name of the app
    event AppCreated(address indexed appAddress, string id, string name);

    /// @dev Emitted when an app transfer is approved
    /// @param appAddress The address of the app being transferred
    /// @param newOwner The address approved to receive the app
    event AppTransferApproved(address indexed appAddress, address indexed newOwner);

    /// @dev Emitted when an app transfer is completed
    /// @param appAddress The address of the transferred app
    /// @param newOwner The address that received the app ownership
    event AppTransferred(address indexed appAddress, address indexed newOwner);

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
        bytes32 storagePosition = DEV_ACCOUNT_APPS_V1;

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
     * @dev Creates a new app contract (owner only)
     * @param _id The unique identifier for the app
     * @param _name The display name of the app
     * @param _description The description of the app
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier
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
     * @dev Creates a new app contract via multicall
     * @param sender The address initiating the multicall
     * @param _id The unique identifier for the app
     * @param _name The display name of the app
     * @param _description The description of the app
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier
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
     * @dev Internal function to create an app with validation
     * @param _id The unique identifier for the app
     * @param _name The display name of the app
     * @param _description The description of the app
     * @param _protocolId The protocol identifier
     * @param _platformId The platform identifier
     * @param _categoryId The category identifier
     */
    function _createApp(
        string memory _id,
        string memory _name,
        string memory _description,

        uint16 _protocolId,
        uint16 _platformId,
        uint16 _categoryId
    ) private {
        bytes32 idHash = keccak256(bytes(_id));
        PublisherAccountAppsPluginV1State storage state = state();
        
        if (state.apps[idHash] != address(0)) {
            revert PublisherAccountAppsPluginError(APP_ALREADY_EXISTS);
        }

        bytes memory bytecode = _getBytecode(
            _id, _name, _description,
            _protocolId, _platformId, _categoryId
        );
        address appAddress = Create2.deploy(0, idHash, bytecode);

        state.apps[idHash] = appAddress;
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
        
        bytes memory constructorArgs = abi.encode(
            address(this),
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
        
        return abi.encodePacked(type(AppAsset).creationCode, constructorArgs);
    }

    /**
     * @dev Retrieves the address of an app by its ID
     * @param id The unique identifier of the app
     * @return app The address of the app contract, or zero address if not found
     */
    function getAppById(string calldata id) external view returns (address) {
        bytes32 idHash = keccak256(bytes(id));
        PublisherAccountAppsPluginV1State storage state = state();
        return state.apps[idHash];
    }

    /**
     * @dev Approves a transfer of app ownership to a new owner (owner only)
     * @notice Only one pending transfer can exist per app at a time. Approving a new transfer overwrites any previous approval.
     * @param id The unique identifier of the app
     * @param newOwner The address that will be approved to accept the transfer
     * @custom:throws APP_NOT_FOUND if the app doesn't belong to this publisher account
     */
    function approveAppTransfer(string calldata id, address newOwner) external onlyOwner {
        _approveAppTransfer(id, newOwner);
    }

    /**
     * @dev Approves a transfer of app ownership to a new owner via multicall
     * @param sender The address initiating the multicall
     * @param id The unique identifier of the app
     * @param newOwner The address that will be approved to accept the transfer
     * @custom:throws APP_NOT_FOUND if the app doesn't belong to this publisher account
     */
    function approveAppTransfer(address sender, string calldata id, address newOwner) external onlyMulticall {
        _checkOwner(sender);
        _approveAppTransfer(id, newOwner);
    }

    /**
     * @dev Internal function to approve app transfer
     * @param id The unique identifier of the app
     * @param newOwner The address that will be approved to accept the transfer
     */
    function _approveAppTransfer(string calldata id, address newOwner) private {
        bytes32 idHash = keccak256(bytes(id));
        PublisherAccountAppsPluginV1State storage s = state();
        address app = s.apps[idHash];

        if (app == address(0)) {
            revert PublisherAccountAppsPluginError(APP_NOT_FOUND);
        }

        s.pendingTransfers[idHash] = newOwner;

        emit AppTransferApproved(app, newOwner);
    }

    /**
     * @dev Transfers an app record from another publisher to this publisher.
     * @notice Calls commitAppTransfer on the old publisher and records the app under this publisher.
     * @param publisher The address of the old publisher account
     * @param id The unique identifier of the app to transfer
     * @custom:throws APP_ALREADY_EXISTS if an app with the given ID already exists here
     */
    function transferAppFrom(address publisher, string calldata id) external onlyOwner {
        _transferAppFrom(publisher, id);
    }

    /**
     * @dev Transfers an app record from another publisher to this publisher via multicall.
     * @param sender The address initiating the multicall
     * @param publisher The address of the old publisher account
     * @param id The unique identifier of the app to transfer
     * @custom:throws APP_ALREADY_EXISTS if an app with the given ID already exists here
     */
    function transferAppFrom(address sender, address publisher, string calldata id) external onlyMulticall {
        _checkOwner(sender);
        _transferAppFrom(publisher, id);
    }

    /**
     * @dev Internal function to transfer an app record from another publisher.
     * @param publisher The address of the old publisher account
     * @param id The unique identifier of the app to transfer
     */
    function _transferAppFrom(address publisher, string calldata id) private {
        bytes32 idHash = keccak256(bytes(id));

        address app = PublisherAccountAppsPluginV1(publisher)
            .commitAppTransfer(idHash);

        PublisherAccountAppsPluginV1State storage s = state();

        if (s.apps[idHash] != address(0)) {
            revert PublisherAccountAppsPluginError(APP_ALREADY_EXISTS);
        }

        s.apps[idHash] = app;
    }

    /**
     * @dev Called by the new publisher to take an app from this publisher.
     * @notice Only the approved recipient can call this to complete the transfer.
     * @param idHash The keccak256 hash of the app's string ID
     * @return app The address of the app being transferred
     * @custom:throws TRANSFER_NOT_APPROVED if caller is not the approved recipient
     */
    function commitAppTransfer(bytes32 idHash) public returns (address) {
        PublisherAccountAppsPluginV1State storage s = state();
        address approvedOwner = s.pendingTransfers[idHash];

        if (approvedOwner != msg.sender) {
            revert PublisherAccountAppsPluginError(TRANSFER_NOT_APPROVED);
        }

        address app = s.apps[idHash];

        delete s.apps[idHash];
        delete s.pendingTransfers[idHash];
        TransferableOwner(app)
            .transferOwnership(msg.sender);

        emit AppTransferred(app, msg.sender);

        return app;
    }
}