// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @title StringVerifier
 * @dev Library for validating string properties
 * @notice Provides utilities for verifying string length constraints
 */
library StringVerifier {
    /**
     * @dev Validates that a string length falls within specified bounds
     * @param _str The string to validate
     * @param min The minimum allowed length (inclusive)
     * @param max The maximum allowed length (inclusive)
     * @return True if the string length is within bounds, false otherwise
     */
    function isValidLength(string memory _str, uint256 min, uint256 max) internal pure returns (bool) {
        bytes memory strBytes = bytes(_str);

        if (strBytes.length < min) {
            return false;
        }

        if (strBytes.length > max) {
            return false;
        }

        return true;
    }
}
