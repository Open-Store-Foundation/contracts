// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @title BitmaskComparator
 * @dev Library for comparing 2-bit pair bitmasks with support for ignoring empty slots
 * @notice Provides functions for comparing 2-bit pair bitmasks where 00 represents empty/unavailable slots
 */
library BitmaskComparator {

    uint256 private constant MASK_HIGH_BITS = 0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
    uint256 private constant MASK_LOW_BITS = 0x5555555555555555555555555555555555555555555555555555555555555555;

    /**
     * @dev For a given mask, creates an "availability mask" where every 2-bit pair that is not 00 becomes 11
     * @notice This is a helper function for compareMasks that identifies available slots
     * @param m The input mask to process
     * @return availMask The availability mask where 11 indicates available slots and 00 indicates empty slots
     */
    function getAvailabilityMask(uint256 m) internal pure returns (uint256 availMask) {
        // Find pairs where any bit is set (i.e., not 00).
        // The result is stored in the low bit of each pair (e.g., 01).
        uint256 anyBitSet = ((m & MASK_HIGH_BITS) >> 1) | (m & MASK_LOW_BITS);

        // Expand the low bit to fill the pair (01 -> 11).
        // x | (x << 1) is equivalent to x * 3 for this pattern.
        assembly {
            availMask := mul(anyBitSet, 3)
        }
    }

    /**
     * @dev Compares two masks, ignoring 2-bit slots where either mask has 00
     * @notice Only compares slots where both masks have non-zero values
     * @param m1 The first mask to compare
     * @param m2 The second mask to compare
     * @return isEqual True if masks are equal in all available slots, false otherwise
     */
    function compareMasks(uint256 m1, uint256 m2) internal pure returns (bool isEqual) {
        // The comparison mask marks with `11` the pairs where BOTH are available.
        uint256 comparisonMask = getAvailabilityMask(m1) & getAvailabilityMask(m2);

        // Gas-optimized approach using XOR and ISZERO.
        // Find all differences and filter by the comparison mask.
        // If the result is zero, there are no relevant differences.
        assembly {
            let diff := xor(m1, m2)
            let relevantDiff := and(diff, comparisonMask)
            isEqual := iszero(relevantDiff)
        }
    }
}
