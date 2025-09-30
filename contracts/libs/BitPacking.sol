// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

library BitPacking {
    
    function unpackBalance(uint256 packed) internal pure returns (uint128) {
        return uint128(packed);
    }
    
    function unpackPower(uint256 packed) internal pure returns (uint128) {
        return uint128(packed >> 128);
    }
    
    function packBalanceAndPower(uint128 balance, uint128 power) internal pure returns (uint256) {
        return (uint256(power) << 128) | balance;
    }
    
    function updateBalance(uint256 packed, uint128 newBalance) internal pure returns (uint256) {
        uint128 power = unpackPower(packed);
        return packBalanceAndPower(newBalance, power);
    }
    
    function addBalance(uint256 packed, uint128 amount) internal pure returns (uint256) {
        uint128 balance = unpackBalance(packed);
        uint128 power = unpackPower(packed);
        return packBalanceAndPower(balance + amount, power);
    }
    
    function unpackVoteBalance(uint256 packed) internal pure returns (uint128) {
        return uint128(packed);
    }
    
    function unpackVotePower(uint256 packed) internal pure returns (uint120) {
        return uint120(packed >> 128);
    }
    
    function unpackVoteStatus(uint256 packed) internal pure returns (uint8) {
        return uint8(packed >> 248);
    }
    
    function packVoteData(uint128 balance, uint120 power, uint8 status) internal pure returns (uint256) {
        return (uint256(status) << 248) | (uint256(power) << 128) | balance;
    }
}
