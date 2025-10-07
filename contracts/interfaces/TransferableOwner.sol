// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/**
 * @title TransferableOwner
 * @dev Minimal interface for contracts that support ownership transfer
 */
interface TransferableOwner {
    /**
     * @dev Transfers ownership to a new owner
     * @param newOwner Recipient of ownership rights
     */
    function transferOwnership(address newOwner) external;
}
