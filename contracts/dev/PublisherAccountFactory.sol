// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {IContractStorage} from "../common/ContractStorage.sol";
import {ITrustedCall} from "../multicall/ITrustedCall.sol";
import {Trustable} from "../multicall/Trustable.sol";
import {TrustedCalldata} from "../multicall/TrustedCalldata.sol";
import {PublisherAccount} from "./PublisherAccount.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title PublisherAccountFactory
 * @dev Factory contract for creating PublisherAccount contracts using CREATE2
 * @notice Provides deterministic deployment of publisher accounts with predictable addresses
 */
contract PublisherAccountFactory is Trustable, ITrustedCall {

    /// @dev Custom error for factory related failures
    /// @param code Error code indicating the specific failure type
    error DevFactoryError(uint32 code);

    // Error Codes
    uint32 constant private DEV_ALREADY_EXISTS = 1;

    /// @dev Emitted when a new publisher account is created
    /// @param owner The owner address of the created account
    /// @param account The address of the created publisher account
    event PublisherAccountCreated(address indexed owner, address account, string name);

    // Const
    bytes32 public constant DEV_ACCOUNT_PLUGINS = keccak256("openstore.plugins.default.PublisherAccount.v1");

    // Storage
    address private immutable contracts;
    mapping(address => mapping(bytes32 => address)) private accounts;

    /**
     * @dev Initializes the factory with contract storage address
     * @param _contracts Address of the contract storage for default plugin configurations
     */
    constructor(address _contracts) {
        contracts = _contracts;
    }

    /**
     * @dev Executes a trusted call via multicall
     * @param call The trusted call data to execute
     */
    function trustedCall(TrustedCalldata memory call) onlyMulticall external payable virtual override {
        Address.functionDelegateCall(
            call.manager,
            call.data
        );
    }

    /**
     * @dev Retrieves the address of a publisher account by owner and publisher ID
     * @param owner The owner address
     * @param publisherId The publisher identifier hash
     * @return The address of the publisher account, or zero address if not found
     */
    function getAddressById(address owner, bytes32 publisherId) external view returns (address) {
        return accounts[owner][publisherId];
    }

    /**
     * @dev Computes the deterministic address where a publisher account will be deployed
     * @param owner The owner address for the account
     * @param name The name of the publisher account
     * @return The computed address for the publisher account
     */
    function computeAccountAddress(address owner, string calldata name) external view returns (address) {
        bytes32 nameHash = keccak256(bytes(name));
        bytes memory bytecode = _getBytecode(owner, name);
        return Create2.computeAddress(nameHash, keccak256(bytecode));
    }

    /**
     * @dev Creates a new publisher account for the caller
     * @param name The name of the publisher account
     */
    function createAccount(string calldata name) external {
        _createAccount(msg.sender, name);
    }

    /**
     * @dev Creates a new publisher account via multicall
     * @param owner The owner address for the account
     * @param name The name of the publisher account
     */
    function createAccount(address owner, string calldata name) external onlyMulticall {
        _createAccount(owner, name);
    }

    /**
     * @dev Internal function to create a publisher account with validation
     * @param owner The owner address for the account
     * @param name The name of the publisher account
     */
    function _createAccount(address owner, string calldata name) private {
        bytes32 nameHash = keccak256(bytes(name));
        if (accounts[owner][nameHash] != address(0)) {
            revert DevFactoryError(DEV_ALREADY_EXISTS);
        }

        bytes memory bytecode = _getBytecode(owner, name);
        address accountAddr = Create2.deploy(0, nameHash, bytecode);
        
        accounts[owner][nameHash] = accountAddr;

        emit PublisherAccountCreated(owner, accountAddr, name);
    }

    /**
     * @dev Generates the bytecode for deploying a publisher account
     * @param owner The owner address for the account
     * @param name The name of the publisher account
     * @return The complete bytecode for publisher account deployment
     */
    function _getBytecode(address owner, string memory name) private view returns (bytes memory) {
        (address[] memory addr, bytes[] memory data, bytes4[][] memory selectors) =
            IContractStorage(contracts)
                    .getDefaultPluginsById(DEV_ACCOUNT_PLUGINS);
        
        bytes memory constructorArgs = abi.encode(
            owner,
            name,
            addr,
            data,
            selectors
        );
        
        return abi.encodePacked(type(PublisherAccount).creationCode, constructorArgs);
    }
}
