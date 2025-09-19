// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @title Named
 * @dev Interface for contracts that have a name property
 * @notice Provides a standard way to retrieve the name of a contract
 */
interface Named {
    /**
     * @dev Returns the name of the contract
     * @return The name as a string
     */
    function getName() external view returns (string memory);
}
