// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @title VersionableOwner
 * @dev Interface for contracts that track ownership versions
 * @notice Provides a way to retrieve the current version of ownership information
 */
interface VersionableOwner {
    /**
     * @dev Returns the current version of ownership information
     * @return The current ownership version number
     */
    function ownerVersion() external view returns (uint256);
}
