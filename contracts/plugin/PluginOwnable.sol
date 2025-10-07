// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {PluginOwnerStorage} from "./PluginOwnerStorage.sol";

/**
 * @title PluginOwnable
 * @dev Abstract contract providing ownership for plugin-managed contracts using diamond storage
 * @notice Supplies owner-only access control with storage isolated via `PluginOwnerStorage`
 */
abstract contract PluginOwnable is Context {

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    /// @dev Emitted when ownership is transferred from one account to another
    /// @param previousOwner The address of the previous owner
    /// @param newOwner The address of the new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner(_msgSender());
        _;
    }

    /**
     * @dev Reverts if the provided address is not the owner
     * @param sender The address to validate as owner
     */
    function _checkOwner(address sender) internal view virtual {
        if (owner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
    }

    /**
     * @dev Returns the address of the current owner
     */
    function owner() public view virtual returns (address) {
        return PluginOwnerStorage.ownerData().owner;
    }
}

abstract contract PluginOwner is PluginOwnable {

    /**
     * @dev Initializes and sets the provided address as the initial owner
     * @param initialOwner The address to set as the initial owner
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }

        PluginOwnerStorage.ownerData().owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }
}
