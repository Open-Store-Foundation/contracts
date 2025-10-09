// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title Trustable
 * @dev Abstract contract providing multicall authorization functionality
 * @notice Allows contracts to restrict certain functions to be called only by authorized multicall contracts
 */
abstract contract Trustable is Context {

    address private constant MULTICALL = 0x3f7AdDD276bC5c1a2Fffb329DD718f1fa0625D84;

    /// @dev Custom error thrown when an unauthorized account attempts to call a multicall-only function
    /// @param account The unauthorized account address
    error MulticallUnauthorizedAccount(address account);

    /**
     * @dev Modifier that restricts function access to authorized multicall contracts only
     */
    modifier onlyMulticall() {
        _checkMulticall(_msgSender());
        _;
    }

    /**
     * @dev Verifies that the sender is an authorized multicall contract
     * @param sender The address to verify
     * @notice Throws MulticallUnauthorizedAccount if sender is not authorized
     */
    function _checkMulticall(address sender) internal view virtual {
        if (multicall() != sender) {
            revert MulticallUnauthorizedAccount(sender);
        }
    }

    /**
     * @dev Returns the address of the authorized multicall contract
     * @return The multicall contract address
     */
    function multicall() public view virtual returns (address) {
        return MULTICALL;
    }
}
