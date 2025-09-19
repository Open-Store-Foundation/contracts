// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @title BytesParser
 * @dev Library for parsing different data types from byte arrays
 * @notice Provides utilities for extracting addresses and uint256 values from byte arrays at specific offsets
 */
library BytesParser {

    /**
     * @dev Extracts an address from a byte array at a specific offset
     * @param _bytes The byte array to parse
     * @param _offset The offset position to start reading from
     * @return The extracted address
     * @notice Requires at least 20 bytes available from the offset position
     */
    function toAddress(bytes memory _bytes, uint256 _offset) internal pure returns (address) {
        require(_bytes.length >= _offset + 20, "toAddress_outOfBounds");
        address tempAddress;
        assembly {
            tempAddress := mload(add(add(_bytes, 0x20), _offset))
            tempAddress := shr(96, tempAddress) // Shift right by 96 bits to extract the least significant 20 bytes
        }
        return tempAddress;
    }

    /**
     * @dev Extracts a uint256 value from a byte array at a specific offset
     * @param _bytes The byte array to parse
     * @param _offset The offset position to start reading from
     * @return The extracted uint256 value
     * @notice Requires at least 32 bytes available from the offset position
     */
    function toUint256(bytes memory _bytes, uint256 _offset) internal pure returns (uint256) {
        require(_bytes.length >= _offset + 32, "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _offset)) // Load 32 bytes from memory at offset
        }

        return tempUint;
    }
}
