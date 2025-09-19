// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {BytesParser} from "../libs/BytesParser.sol";
import {ITrustedCall} from "./ITrustedCall.sol";
import {TrustedCalldata} from "./TrustedCalldata.sol";

/**
 * @title TrustedMulticall
 * @dev Contract for executing multiple trusted calls in a single transaction
 * @notice Provides secure batch execution of calls with sender verification
 */
contract TrustedMulticall {

    using BytesParser for bytes;

    /// @dev Custom error thrown when the message sender doesn't match the sender in call data
    /// @param msgSender The actual message sender
    /// @param calldataSender The sender specified in the call data
    error MsgSenderNotMatchToCalldata(address msgSender, address calldataSender);
    
    /// @dev Custom error thrown when a call fails without providing a reason
    /// @param index The index of the failed call in the batch
    error EmptyReason(uint256 index);

    /**
     * @dev Executes multiple trusted calls in a single transaction
     * @param calls Array of trusted call data to execute
     * @notice Verifies sender authenticity and executes each call through the ITrustedCall interface
     */
    function multicall(TrustedCalldata[] memory calls) external payable {
        for (uint256 i = 0; i < calls.length; i++) {
            TrustedCalldata memory call = calls[i];

            address sender = call.data.toAddress(16); // 4 selector + (32 - 20) slot
            if (msg.sender != sender) {
                revert MsgSenderNotMatchToCalldata(msg.sender, sender);
            }

            bytes memory payload = abi.encodeCall(
                ITrustedCall.trustedCall,
                (call)
            );

            (bool success, bytes memory result) = payable(call.manager).call{value: call.value}(payload);

            if (!success) {
                if (result.length == 0) {
                    revert EmptyReason(i);
                }

                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        }
    }
}
