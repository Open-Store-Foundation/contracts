// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {TrustedMulticall} from "../multicall/TrustedMulticall.sol";

/**
 * @title ContractsFactory
 * @dev Factory contract for deploying TrustedMulticall contracts using CREATE2
 * @notice Provides deterministic deployment of multicall contracts with predictable addresses
 */
contract ContractsFactory is Ownable {

    /// @dev Emitted when a new contract is deployed
    /// @param contractAddress The address of the deployed contract
    event ContractDeployed(address contractAddress);

    constructor(address owner) Ownable(owner) {}

    /**
     * @dev Deploys a TrustedMulticall contract if one doesn't already exist at the computed address
     * @notice Uses CREATE2 for deterministic deployment, allowing the same address across different chains
     */
    function createMulticall(uint256 nonce) external {
        address contractAddress = multicallAddress(nonce);

        uint length = contractAddress.code.length;
        if (length > 0) {
            return;
        }

        bytes memory bytecode = multicallBytecode();
        address multicall = Create2.deploy(0, bytes32(nonce), bytecode);
        emit ContractDeployed(multicall);
    }

    /**
     * @dev Computes the address where the TrustedMulticall contract will be deployed
     * @return The computed address for the multicall contract
     */
    function multicallAddress(uint256 nonce) public view returns (address) {
        bytes memory bytecode = multicallBytecode();
        address multicall = Create2.computeAddress(bytes32(nonce), keccak256(bytecode));
        return multicall;
    }

    /**
     * @dev Returns the complete bytecode for deploying a TrustedMulticall contract
     * @return The bytecode including constructor parameters
     */
    function multicallBytecode() private pure returns (bytes memory) {
        bytes memory bytecode = type(TrustedMulticall).creationCode;

        return abi.encodePacked(
            bytecode,
            abi.encode()
        );
    }
}
