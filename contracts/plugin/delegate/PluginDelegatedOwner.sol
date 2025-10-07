// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {PluginOwnerStorage} from "../PluginOwnerStorage.sol";
import {PluginOwnable} from "../PluginOwnable.sol";


/**
 * @title PluginDelegatedOwner
 * @dev Abstract contract providing delegated ownership checks for plugin-managed contracts
 * @notice Allows a contract to authorize a delegate owner (e.g., a publisher account) distinct from the direct owner
 */
abstract contract PluginDelegatedOwner is Context {

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableDelegateUnauthorizedAccount(address account);

    /**
     * @dev Restricts function to the delegated owner
     * @notice Reverts if the caller is not the delegated owner
     */
    modifier onlyDelegateOwner() {
        _checkDelegateOwner(_msgSender());
        _;
    }

    /**
     * @dev Checks that the provided address is the delegated owner
     * @param sender The address to validate as delegated owner
     */
    function _checkDelegateOwner(address sender) internal view virtual {
        if (delegateOwner() != sender) {
            revert OwnableDelegateUnauthorizedAccount(sender);
        }
    }

    /**
     * @dev Returns the address of the delegated owner contract
     * @return The delegated owner (intermediate owner, e.g., a `PublisherAccount`)
     */
    function delegateOwner() public view virtual returns (address) {
        return PluginOwnable(PluginOwnerStorage.ownerData().owner)
            .owner();
    }
}

