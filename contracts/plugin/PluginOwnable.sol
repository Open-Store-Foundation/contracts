// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {PluginOwnerStorage} from "./PluginOwnerStorage.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title PluginOwnable
 * @dev Abstract contract providing ownership functionality for plugins using diamond storage
 * @notice Provides owner-only access control using diamond storage pattern
 */
abstract contract PluginOwnable is Context {

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner(_msgSender());
        _;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner(address sender) internal view virtual {
        if (owner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return PluginOwnerStorage.ownerData().owner;
    }
}

/**
 * @title PluginOwner
 * @dev Abstract contract extending PluginOwnable with ownership transfer capabilities
 * @notice Provides complete ownership management including transfer and renunciation
 */
abstract contract PluginOwner is PluginOwnable {

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    /// @dev Emitted when ownership is transferred from one account to another
    /// @param previousOwner The address of the previous owner
    /// @param newOwner The address of the new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the provided address as the initial owner
     * @param initialOwner The address to set as the initial owner
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
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
        require(PluginOwnerStorage.ownerData().owner == newOwner, "wrong");
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
