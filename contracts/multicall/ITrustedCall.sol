// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "./TrustedCalldata.sol";

/**
 * @title ITrustedCall
 * @dev Interface for contracts that can receive trusted calls from the multicall system
 * @notice Defines the standard interface for executing trusted calls with verified sender information
 */
interface ITrustedCall {
    /**
     * @dev Executes a trusted call with the provided call data
     * @param call The trusted call data containing manager, plugin, data, and value information
     * @notice This function should only be callable by authorized multicall contracts
     */
    function trustedCall(TrustedCalldata memory call) external payable;
}
