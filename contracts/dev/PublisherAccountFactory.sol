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

    /**
     * @notice Initialize factory with contract storage address
     * @param _contracts Contract storage used to read default plugin configuration
     */
    constructor(address _contracts) {
        contracts = _contracts;
    }

    /**
     * @notice Execute a trusted call via multicall
     * @param call Trusted call payload
     */
    function trustedCall(TrustedCalldata memory call) onlyMulticall external payable virtual override {
        Address.functionDelegateCall(
            call.manager,
            call.data
        );
    }

    

    /**
     * @notice Compute deterministic address of a publisher account deployment
     * @param owner Account owner
     * @param name Publisher account name
     * @return predicted Predicted deployment address
     */
    function computeAccountAddress(address owner, string calldata name) external view returns (address) {
        bytes32 nameHash = keccak256(bytes(name));
        (address[] memory addr, bytes[] memory data, bytes4[][] memory selectors) = _getDefaultPlugins();
        bytes memory bytecode = _getBytecode(owner, name, addr, data, selectors);
        return Create2.computeAddress(nameHash, keccak256(bytecode));
    }

    /**
     * @notice Compute deterministic address of a publisher account with custom plugins
     * @param owner Account owner
     * @param name Publisher account name
     * @param addr Plugin implementation addresses
     * @param data Plugin initialization calldata
     * @param selectors Plugin function selectors per facet
     * @return predicted Predicted deployment address
     */
    function computeAccountAddress(
        address owner,
        string calldata name,
        address[] calldata addr,
        bytes[] calldata data,
        bytes4[][] calldata selectors
    ) external view returns (address) {
        bytes32 nameHash = keccak256(bytes(name));
        address[] memory addrM = abi.decode(abi.encode(addr), (address[]));
        bytes[] memory dataM = abi.decode(abi.encode(data), (bytes[]));
        bytes4[][] memory selectorsM = abi.decode(abi.encode(selectors), (bytes4[][]));
        bytes memory bytecode = _getBytecode(owner, name, addrM, dataM, selectorsM);
        return Create2.computeAddress(nameHash, keccak256(bytecode));
    }

    /**
     * @dev Creates a new publisher account for the caller
     * @param name The name of the publisher account
     */
    function createAccount(string calldata name) external {
        (address[] memory addr, bytes[] memory data, bytes4[][] memory selectors) = _getDefaultPlugins();
        _createAccount(msg.sender, name, addr, data, selectors);
    }

    /**
     * @dev Creates a new publisher account via multicall
     * @param owner The owner address for the account
     * @param name The name of the publisher account
     */
    function createAccount(address owner, string calldata name) external onlyMulticall {
        (address[] memory addr, bytes[] memory data, bytes4[][] memory selectors) = _getDefaultPlugins();
        _createAccount(owner, name, addr, data, selectors);
    }

    /**
     * @notice Create a new publisher account using custom plugin configuration
     * @param name Publisher account name
     * @param addr Plugin implementation addresses
     * @param data Plugin initialization calldata
     * @param selectors Plugin function selectors per facet
     */
    function createAccount(
        string calldata name,
        address[] calldata addr,
        bytes[] calldata data,
        bytes4[][] calldata selectors
    ) external {
        _createAccount(msg.sender, name, addr, data, selectors);
    }

    /**
     * @notice Create a new publisher account using custom plugins via multicall
     * @param owner Account owner
     * @param name Publisher account name
     * @param addr Plugin implementation addresses
     * @param data Plugin initialization calldata
     * @param selectors Plugin function selectors per facet
     */
    function createAccount(
        address owner,
        string calldata name,
        address[] calldata addr,
        bytes[] calldata data,
        bytes4[][] calldata selectors
    ) external onlyMulticall {
        _createAccount(owner, name, addr, data, selectors);
    }

    function _createAccount(
        address owner,
        string calldata name,
        address[] memory addr,
        bytes[] memory data,
        bytes4[][] memory selectors
    ) private {
        bytes32 nameHash = keccak256(bytes(name));
        bytes memory bytecode = _getBytecode(owner, name, addr, data, selectors);
        address predicted = Create2.computeAddress(nameHash, keccak256(bytecode));
        if (Address.isContract(predicted)) {
            revert DevFactoryError(DEV_ALREADY_EXISTS);
        }
        address accountAddr = Create2.deploy(0, nameHash, bytecode);
        emit PublisherAccountCreated(owner, accountAddr, name);
    }

    function _getBytecode(
        address owner,
        string memory name,
        address[] memory addr,
        bytes[] memory data,
        bytes4[][] memory selectors
    ) private view returns (bytes memory) {
        bytes memory constructorArgs = abi.encode(
            owner,
            name,
            addr,
            data,
            selectors
        );

        return abi.encodePacked(type(PublisherAccount).creationCode, constructorArgs);
    }

    /**
     * @dev Fetches default plugin configuration from contract storage
     */
    function _getDefaultPlugins()
        private
        view
        returns (
            address[] memory addr,
            bytes[] memory data,
            bytes4[][] memory selectors
        )
    {
        (addr, data, selectors) = IContractStorage(contracts).getDefaultPluginsById(DEV_ACCOUNT_PLUGINS);
    }
}
