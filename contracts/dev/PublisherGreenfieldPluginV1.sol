// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "../common/ContractStorage.sol";
import "../plugin/Plugin.sol";
import "./PublisherFacetStorageV1.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IBucketHub.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IGreenfieldExecutor.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/IPermissionHub.sol";
import "@bnb-chain/greenfield-contracts/contracts/interface/ITokenHub.sol";
import "@bnb-chain/greenfield-contracts/contracts/middle-layer/resource-mirror/storage/BucketStorage.sol";

/**
 * @title PublisherGreenfieldPluginV1
 * @dev Plugin that provides integration with BNB Greenfield blockchain for storage operations
 * @notice Enables publisher accounts to interact with Greenfield for decentralized storage
 */
contract PublisherGreenfieldPluginV1 is Plugin {

    address private immutable gfExecutorAddress;
    address private immutable gfPermissionHubAddress;
    address private immutable gfTokenHubAddress;
    address private immutable gfBucketHubAddress;

    /**
     * @dev Initializes the plugin with Greenfield contract addresses
     * @param _gfExecutorAddress Address of the Greenfield executor contract
     * @param _gfPermissionHubAddress Address of the Greenfield permission hub
     * @param _gfTokenHubAddress Address of the Greenfield token hub
     * @param _gfBucketHubAddress Address of the Greenfield bucket hub
     */
    constructor(
        address _gfExecutorAddress,
        address _gfPermissionHubAddress,
        address _gfTokenHubAddress,
        address _gfBucketHubAddress
    ) {
        gfExecutorAddress = _gfExecutorAddress;
        gfPermissionHubAddress = _gfPermissionHubAddress;
        gfTokenHubAddress = _gfTokenHubAddress;
        gfBucketHubAddress = _gfBucketHubAddress;
    }

    /**
     * @dev Initializes the plugin (implementation required by Plugin interface)
     * @param data Initialization data (unused in this implementation)
     */
    function initialize(bytes memory data) external override payable {}

    /**
     * @dev Creates a storage space (bucket) on Greenfield (owner only)
     * @param name The name of the storage space
     * @param spAddress The storage provider address
     * @param primarySpApprovalExpiredHeight Expiration height for SP approval
     * @param globalVirtualGroupFamilyId Virtual group family identifier
     * @param primarySpSignature Primary storage provider signature
     * @param chargedReadQuota Read quota to be charged
     * @param extraData Additional data for the creation
     */
    function createSpace(
        string calldata name,
        address spAddress,
        uint64 primarySpApprovalExpiredHeight,
        uint32 globalVirtualGroupFamilyId,
        bytes calldata primarySpSignature,
        uint32 chargedReadQuota,
        bytes calldata extraData
    ) external payable onlyOwner {
        _createSpace(
            name, spAddress,
            primarySpApprovalExpiredHeight, globalVirtualGroupFamilyId,
            primarySpSignature, chargedReadQuota, extraData
        );
    }

    /**
     * @dev Creates a storage space via multicall
     * @param sender The address initiating the multicall
     * @param name The name of the storage space
     * @param spAddress The storage provider address
     * @param primarySpApprovalExpiredHeight Expiration height for SP approval
     * @param globalVirtualGroupFamilyId Virtual group family identifier
     * @param primarySpSignature Primary storage provider signature
     * @param chargedReadQuota Read quota to be charged
     * @param extraData Additional data for the creation
     */
    function createSpace(
        address sender,
        string calldata name,
        address spAddress,
        uint64 primarySpApprovalExpiredHeight,
        uint32 globalVirtualGroupFamilyId,
        bytes calldata primarySpSignature,
        uint32 chargedReadQuota,
        bytes calldata extraData
    ) external payable onlyMulticall {
        _checkOwner(sender);
        _createSpace(
            name, spAddress,
            primarySpApprovalExpiredHeight, globalVirtualGroupFamilyId,
            primarySpSignature, chargedReadQuota, extraData
        );
    }

    /**
     * @dev Internal function to create a storage space on Greenfield
     * @param name The name of the storage space
     * @param spAddress The storage provider address
     * @param primarySpApprovalExpiredHeight Expiration height for SP approval
     * @param globalVirtualGroupFamilyId Virtual group family identifier
     * @param primarySpSignature Primary storage provider signature
     * @param chargedReadQuota Read quota to be charged
     * @param extraData Additional data for the creation
     */
    function _createSpace(
        string calldata name,
        address spAddress,
        uint64 primarySpApprovalExpiredHeight,
        uint32 globalVirtualGroupFamilyId,
        bytes calldata primarySpSignature,
        uint32 chargedReadQuota,
        bytes calldata extraData
    ) private  {
        address current = address(this);

        BucketStorage.CreateBucketSynPackage memory createPackage = BucketStorage.CreateBucketSynPackage({
            creator: current,
            name: name,
            visibility: BucketStorage.BucketVisibilityType.PublicRead,
            paymentAddress: current,
            primarySpAddress: spAddress,
            primarySpApprovalExpiredHeight: primarySpApprovalExpiredHeight,
            globalVirtualGroupFamilyId: globalVirtualGroupFamilyId,
            primarySpSignature: primarySpSignature,
            chargedReadQuota: chargedReadQuota,
            extraData: extraData
        });

        IBucketHub(gfBucketHubAddress)
            .createBucket{value: msg.value}(createPackage);
    }

    /**
     * @dev Executes messages on Greenfield (owner only)
     * @param types Array of message types to execute
     * @param data Array of message data corresponding to each type
     */
    function executeMsg(uint8[] memory types, bytes[] memory data) external payable onlyOwner {
        _executeMsg(types, data);
    }

    /**
     * @dev Executes messages on Greenfield via multicall
     * @param sender The address initiating the multicall
     * @param types Array of message types to execute
     * @param data Array of message data corresponding to each type
     */
    function executeMsg(address sender, uint8[] memory types, bytes[] memory data) external payable onlyMulticall {
        _checkOwner(sender);
        _executeMsg(types, data);
    }

    /**
     * @dev Internal function to execute messages on Greenfield
     * @param types Array of message types to execute
     * @param data Array of message data corresponding to each type
     */
    function _executeMsg(uint8[] memory types, bytes[] memory data) private  {
        IGreenfieldExecutor(gfExecutorAddress)
            .execute{value: msg.value}(types, data);
    }

    /**
     * @dev Changes permission policy on Greenfield (owner only)
     * @param createPolicyData The policy data to create/change
     */
    function changePolicy(bytes memory createPolicyData) external payable onlyOwner {
        _changePolicy(createPolicyData);
    }

    /**
     * @dev Changes permission policy via multicall
     * @param sender The address initiating the multicall
     * @param createPolicyData The policy data to create/change
     */
    function changePolicy(address sender, bytes memory createPolicyData) external payable onlyMulticall {
        _checkOwner(sender);
        _changePolicy(createPolicyData);
    }

    /**
     * @dev Internal function to change permission policy
     * @param createPolicyData The policy data to create/change
     */
    function _changePolicy(bytes memory createPolicyData) private {
        IPermissionHub(gfPermissionHubAddress)
            .createPolicy{value: msg.value}(createPolicyData);
    }

    /**
     * @dev Tops up the account balance on Greenfield (owner only)
     * @param amount The amount to transfer for top-up
     */
    function topUp(uint256 amount) external payable onlyOwner {
        _topUp(amount);
    }

    /**
     * @dev Tops up the account balance via multicall
     * @param sender The address initiating the multicall
     * @param amount The amount to transfer for top-up
     */
    function topUp(address sender, uint256 amount) external payable onlyMulticall {
        _checkOwner(sender);
        _topUp(amount);
    }

    /**
     * @dev Internal function to top up account balance
     * @param amount The amount to transfer for top-up
     */
    function _topUp(uint256 amount) private {
        ITokenHub(gfTokenHubAddress)
            .transferOut{value: msg.value}(payable(address(this)), amount);
    }
}
