// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @dev Structure representing trusted call data for multicall operations
 * @param manager The address of the manager contract that will receive the call
 * @param plugin The address of the plugin contract being called
 * @param data The encoded function call data
 * @param value The amount of ETH to send with the call
 */
struct TrustedCalldata {
    address manager;
    address plugin;
    bytes data;
    uint256 value;
}
