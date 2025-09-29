// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./OpenStoreStorageV2.sol";

contract OpenStoreV2 {

    constructor(){}

    int256 private constant WITHDRAWAL_PERIOD = 60 * 60 * 24;
    int256 private constant VOTING_PERIOD = 60 * 60 * 24;
    uint256 private constant VALIDATION_FEE = 0.001 ether;
    uint256 private constant MIX_STAKE = 1 ether;

    mapping (uint256 => mapping(uint256 => uint256)) private requests;
    mapping (uint256 => mapping(uint256 => uint256)) private requestsPower;
    mapping (uint256 => mapping(uint256 => uint256)) private statusWinner;

    function topUp() external payable {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();

        require(state.validators[sender].withdrawStatus[sender] >= 0, "");

        state.validators[sender].totalBalance += msg.value;
        if (state.validators[sender].totalBalance > VALIDATION_FEE) {
            state.validators[sender].withdrawStatus[sender] = -1;
        }
    }

    function withdraw() external payable {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();

        int256 time = state.validators[sender].withdrawStatus[sender];
        if (time > 0) {
            require(int256(block.timestamp) - time >= WITHDRAWAL_PERIOD, "");

            payable(msg.sender)
                .transfer(state.validators[sender].totalBalance);

            state.validators[sender].withdrawStatus[sender] = 0;
        } else {
            state.validators[sender].withdrawStatus[sender] = block.timestamp;
        }
    }

    function nextRequestIdToVote() external {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();

    }

    // state.timer[toReqId] = block.timestamp + VOTING_PERIOD
    // state.nextReqIdToVote = toReqId
    function vote(uint256 fromReqId, uint256 toReqId, uint256 result) external {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        if ((toReqId - fromReqId) > 32) {
//            revert OpenStoreError(ERROR_TOO_MANY_REQUESTS_IN_BLOCK);
        }

        if (state.validators[sender].withdrawStatus >= 0) {
//            revert OpenStoreError(ERROR_INVALID_TO_REQUEST_ID);
        }

        if (fromReqId < state.validators[sender].nextRequestIdToVote) {
//            revert OpenStoreError(ERROR_INVALID_TO_REQUEST_ID);
        }

        if (fromReqId < state.nextRequestIdToFinalize) {
//            revert OpenStoreError(ERROR_INVALID_TO_REQUEST_ID);
        }

        if (toReqId >= state.nextRequestIdToCreate) {
//            revert OpenStoreError(ERROR_INVALID_TO_REQUEST_ID);
        }

        uint256 totalBalance = state.validators[sender].totalBalance;
        uint8 status;
        for (uint256 i = fromReqId; i < toReqId; i++) {
            status = (result >> i * 8);
            uint256 votingBalance = requests[i][status] + totalBalance;
            requests[i][status] = votingBalance;
            requestsPower[i][msg.sender] = status; // (status, validator.votePower);// or -1

            uint8 oldStatusWinner = statusWinner[i];
            if (status != oldStatusWinner && votingBalance > requests[i][oldStatusWinner]) {
                statusWinner[i] = status;
            }
        }

        state.validators[sender].nextRequestIdToVote = toReqId;
//        emit Voted(sender, fromReqId, toReqId, result);
    }

    function claim() external {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();

        uint256 lastClaimReqId = state.validators[sender].nextRequestIdToClaim;
        uint256 lastFinalizedReqId = state.nextRequestIdToFinalize;
        require(lastClaimReqId < lastFinalizedReqId, "");

        uint256 totalReward = 0;

        for (uint256 i = lastClaimReqId; i < lastFinalizedReqId; i++) {
            uint256 statusWinner = statusWinner[i];
            uint totalBalance = requests[i][statusWinner];

            (uint256 status, uint256 balance) = requestsPower[i][msg.sender];
            if (status == statusWinner) {
                uint256 ratio = mulDiv(balance, totalBalance);
                totalReward += (ratio * VALIDATION_FEE);
                delete requestsPower[i][msg.sender];
            }


            state.validators[msg.sender].totalBalance += totalReward;
            state.validators[msg.sender].nextRequestIdToClaim = lastFinalizedReqId - 1;
        }
    }
}
