// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "../Plugin.sol";
import "./PluginDelegatedOwner.sol";

abstract contract DelegatedPlugin is Plugin, PluginDelegatedOwner {}
