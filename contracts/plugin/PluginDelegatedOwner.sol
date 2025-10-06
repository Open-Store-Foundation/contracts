// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "./PluginOwnable.sol";
import {PluginOwnerStorage} from "./PluginOwnerStorage.sol";
import {TransferableOwner} from "../interfaces/TransferableOwner.sol";

/**
 * @title PluginOwnerDelegate
 * @dev Abstract contract that implements delegated ownership pattern for plugins
 * @notice Allows ownership to be delegated through another contract that implements PluginOwnable
 * @custom:security-contact security@openstore.com
 * 
 * This contract enables a two-tier ownership structure:
 * - ownerDelegate: The direct owner stored in storage (e.g., PublisherAccount contract)
 * - owner: The actual owner retrieved by calling owner() on the ownerDelegate
 * 
 * Example: AppAsset -> PublisherAccount -> Actual User
 */
abstract contract PluginDelegatedOwner is PluginOwnable, TransferableOwner {

    /**
     * @dev The caller is not authorized to perform delegate operations
     */
    error OwnableDelegateUnauthorizedAccount(address account);

    /**
     * @dev Modifier that checks if the caller is the owner delegate
     * @notice Reverts if msg.sender is not the ownerDelegate address
     */
    modifier onlyOwnerDelegate() {
        if (ownerDelegate() != msg.sender) {
            revert OwnableDelegateUnauthorizedAccount(msg.sender);
        }
        _;
    }

    /**
     * @dev Returns the actual owner by querying the owner delegate contract
     * @return The address of the actual owner (not the delegate)
     * @notice This follows the delegation chain: calls ownerDelegate().owner()
     */
    function owner() public view virtual override returns (address) {
        return PluginOwnable(ownerDelegate()).owner();
    }

    /**
     * @dev Returns the address of the owner delegate contract
     * @return The address stored as the direct owner in storage
     * @notice This is the intermediate owner (e.g., PublisherAccount address)
     */
    function ownerDelegate() public view virtual returns (address) {
        return PluginOwnerStorage.ownerData().owner;
    }

    /**
     * @dev Transfers the owner delegate to a new PluginOwnable contract
     * @param newOwner The address of the new owner delegate (must implement PluginOwnable)
     * @notice Can only be called by the current owner delegate
     * @custom:throws OwnableInvalidOwner if newOwner is the zero address
     */
    function transferOwnership(address newOwner) external onlyOwnerDelegate {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Internal function to transfer ownership delegate
     * @param newOwner The address of the new owner delegate
     * @notice Emits OwnershipTransferred event
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = PluginOwnerStorage.ownerData().owner;
        PluginOwnerStorage.ownerData().owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

