// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../../interfaces/TransferableOwner.sol";
import "../PluginOwnable.sol";
/**
 * @title PluginOwner
 * @dev Abstract contract extending PluginOwnable with ownership transfer capabilities
 * @notice Provides complete ownership management including transfer and renunciation
 */
abstract contract OwnerTransferPluginV1 is PluginOwnable, TransferableOwner {

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = PluginOwnerStorage.ownerData().owner;
        PluginOwnerStorage.ownerData().owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
