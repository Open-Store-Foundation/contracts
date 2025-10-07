// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @title IOpenStoreRequestHandler
 * @dev Interface for handling validation requests in the OpenStore system
 * @notice Defines callbacks for adding and processing validation requests
 */
interface IOpenStoreRequestHandler {
    /**
     * @dev Called when a new validation request is added to the system
     * @param sender The address that initiated the request
     * @param msgValue The amount of ETH sent with the request
     * @param reqType The type of validation request (e.g., 1 for build validation)
     * @param target The contract address being validated
     * @param data Additional data for the validation request
     * @return The unique request ID that was assigned
     */
    function onAddValidationRequest(
        address sender,
        uint256 msgValue,
        uint256 reqType,
        address target,
        bytes calldata data
    ) external payable returns (uint256);

    /**
     * @dev Called when validation requests are processed and finalized
     * @param result Bitmask indicating the success/failure status of each request
     * @param count The number of requests being processed
     * @param fromRequestId The starting request ID in the batch
     * @notice Processes the results and updates the vault accordingly
     */
    function onRemoveValidationRequests(
        uint256 result,
        uint256 count,
        uint256 fromRequestId
    ) external payable;
} 