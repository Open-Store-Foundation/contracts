// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import {Plugin} from "../plugin/Plugin.sol";
import {TransferableOwner} from "../interfaces/TransferableOwner.sol";

/// @dev Transfer plugin state: idHash -> approved new owner
struct PublisherOwnershipTransferPluginV1AlphaState {
    mapping(bytes32 => address) pendingTransfers;
}

/// @dev Apps plugin state: idHash -> app address
struct PublisherAccountAppsPluginV1AppsState {
    mapping(bytes32 => address) appsHashes;
}

// TODO handle GreenfieldPluginV1 during migration
/**
 * @title PublisherOwnershipTransferPluginV1Alpha
 * @dev Approve/accept app ownership transfers between publisher accounts
 * @notice Keeps pendingTransfers isolated; reads/writes appsHashes shared with apps plugin
 */
contract PublisherOwnershipTransferPluginV1Alpha is Plugin {
    error PublisherAccountAppsPluginError(uint32 code);

    uint32 private constant APP_ALREADY_EXISTS = 1;
    uint32 private constant APP_NOT_FOUND = 2;
    uint32 private constant TRANSFER_NOT_APPROVED = 3;
    uint32 private constant INVALID_APP_OWNER = 4;

    event AppTransferApproved(address indexed appAddress, address indexed oldOwner, address indexed newOwner);
    event AppTransferred(address indexed appAddress, address indexed oldOwner, address indexed newOwner);

    bytes32 private constant PUBLISHER_ACCOUNT_APPS_V1 = keccak256("openstore.plugin.storage.PublisherAccountAppsPlugin.v1");
    bytes32 private constant PUBLISHER_ACCOUNT_APPS_TRANSFERS_V1 = keccak256("openstore.plugin.storage.PublisherOwnershipTransferPlugin.v1");

    /**
     * @dev Access shared apps storage slot used by apps plugin
     */
    function appsState() private pure returns (PublisherAccountAppsPluginV1AppsState storage ds) {
        bytes32 storagePosition = PUBLISHER_ACCOUNT_APPS_V1;
        assembly {
            ds.slot := storagePosition
        }
        return ds;
    }

    /**
     * @dev Access transfer plugin storage slot
     */
    function transfersState() private pure returns (PublisherOwnershipTransferPluginV1AlphaState storage ds) {
        bytes32 storagePosition = PUBLISHER_ACCOUNT_APPS_TRANSFERS_V1;
        assembly {
            ds.slot := storagePosition
        }
        return ds;
    }

    /**
     * @dev Approve a transfer of an app to a new publisher (owner only)
     * @param idHash keccak256 of app id
     * @param newOwner address of publisher to receive the app
     */
    function approveAppTransfer(bytes32 idHash, address newOwner) external onlyOwner {
        _approveAppTransfer(idHash, newOwner);
    }

    /**
     * @dev Approve a transfer via multicall, checking delegated sender
     */
    function approveAppTransfer(address sender, bytes32 idHash, address newOwner) external onlyMulticall {
        _checkOwner(sender);
        _approveAppTransfer(idHash, newOwner);
    }

    function _approveAppTransfer(bytes32 idHash, address newOwner) private {
        PublisherAccountAppsPluginV1AppsState storage a = appsState();
        address app = a.appsHashes[idHash];
        if (app == address(0)) {
            revert PublisherAccountAppsPluginError(APP_NOT_FOUND);
        }
        address owner = address(this);
        if (Ownable(app).owner() != owner) {
            revert PublisherAccountAppsPluginError(INVALID_APP_OWNER);
        }
        transfersState().pendingTransfers[idHash] = newOwner;
        emit AppTransferApproved(app, owner, newOwner);
    }

    /**
     * @dev Accept a transfer from another publisher (owner only)
     * @param publisher old publisher address
     * @param idHash keccak256 of app id
     */
    function acceptAppTransfer(address publisher, bytes32 idHash) external onlyOwner {
        _acceptAppTransfer(publisher, idHash);
    }

    /**
     * @dev Accept a transfer via multicall, checking delegated sender
     */
    function acceptAppTransfer(address sender, address publisher, bytes32 idHash) external onlyMulticall {
        _checkOwner(sender);
        _acceptAppTransfer(publisher, idHash);
    }

    function _acceptAppTransfer(address publisher, bytes32 idHash) private {
        PublisherAccountAppsPluginV1AppsState storage a = appsState();
        if (a.appsHashes[idHash] != address(0)) {
            revert PublisherAccountAppsPluginError(APP_ALREADY_EXISTS);
        }
        address app = PublisherOwnershipTransferPluginV1Alpha(publisher)
            ._commitAppTransfer(address(this), idHash);
        a.appsHashes[idHash] = app;
    }

    /**
     * @dev Finalize transfer called by the new publisher on the old publisher
     * @param newPublisher receiver publisher
     * @param idHash keccak256 of app id
     * @return app app address
     */
    function _commitAppTransfer(address newPublisher, bytes32 idHash) public returns (address) {
        PublisherOwnershipTransferPluginV1AlphaState storage t = transfersState();
        address approvedOwner = t.pendingTransfers[idHash];
        if (approvedOwner != newPublisher) {
            revert PublisherAccountAppsPluginError(TRANSFER_NOT_APPROVED);
        }
        PublisherAccountAppsPluginV1AppsState storage a = appsState();
        address app = a.appsHashes[idHash];
        delete a.appsHashes[idHash];
        delete t.pendingTransfers[idHash];
        TransferableOwner(app).transferOwnership(newPublisher);
        emit AppTransferred(app, address(this), newPublisher);
        return app;
    }
}


