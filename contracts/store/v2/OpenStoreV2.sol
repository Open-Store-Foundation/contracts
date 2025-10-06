// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../../libs/BitPacking.sol";
import "../../libs/BitmaskComparator.sol";
import "../../libs/BytesParser.sol";
import "../../oracle/AssetlinksOracle.sol";
import "../../plugin/PluginOwnable.sol";
import "./OpenStoreStorageV2.sol";

contract OpenStoreV2 is PluginManager {

    using BitPacking for uint256;
    using BytesParser for bytes;

    error OpenStoreError(uint16 code);

    uint16 private constant ERROR_VALIDATOR_UNSUPPORTED_VERSION = 2;
    uint16 private constant ERROR_INSUFFICIENT_STAKE = 4;
    uint16 private constant ERROR_VALIDATOR_NOT_REGISTERED = 5;
    uint16 private constant ERROR_VALIDATOR_IN_WITHDRAWAL = 6;
    uint16 private constant ERROR_REQUESTS_SUSPENDED = 15;
    uint16 private constant ERROR_INCORRECT_VALIDATION_FEE = 16;
    uint16 private constant ERROR_NOT_TARGET_OWNER = 17;
    uint16 private constant ERROR_OWNER_NOT_VERIFIED = 19;
    uint16 private constant ERROR_TOO_MANY_REQUESTS_IN_BLOCK = 22;
    uint16 private constant ERROR_INVALID_TO_REQUEST_ID = 24;
    uint16 private constant ERROR_INVALID_FROM_REQUEST_ID = 25;
    uint16 private constant ERROR_VOTING_PERIOD_EXPIRED = 36;
    uint16 private constant ERROR_BUILD_VERSION_ZERO = 42;
    uint16 private constant ERROR_UNKNOWN_REQUEST_TYPE = 43;
    uint16 private constant ERROR_NO_REWARDS_TO_CLAIM = 45;
    uint16 private constant ERROR_WITHDRAWAL_PERIOD_NOT_ELAPSED = 46;

    int256 private constant WITHDRAWAL_PERIOD = 60 * 60 * 24;
    uint256 private constant VOTING_PERIOD = 60 * 60 * 24;
    uint256 private constant BP_PERCENT = 10000;

    constructor(
        address _owner,
        OpenStoreConfig memory _config
    ) PluginManager(_owner) {
        // Set initial configuration
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();
        OpenStoreStorageV2.setStoreConfig(config, _config);
    }

    event ConfigChanged();

    event WithdrawStarted(address indexed voter);
    event Withdraw(address indexed voter, uint256 amount);
    event TopUp(address indexed voter, uint256 newBalance);
    event Claimed(address indexed voter, uint256 newBalance, uint128 newVotePower);

    event Voted(address indexed voter, uint256 fromReqId, uint256 toReqId, uint256 request, uint128 votePower);

    /////////////////////////////////
    // Configuration Management
    /////////////////////////////////

    /**
     * @notice Gets the minimum required validator version
     * @return The minimum validator version that can participate
     */
    function minValidatorVersion() external view returns (uint64) {
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();
        return config.minValidatorVersion;
    }

    /**
     * @notice Sets the minimum required validator version (owner only)
     * @param newVersion The new minimum validator version
     * @dev Validators below this version cannot participate in validation
     */
    function setMinValidatorVersion(uint64 newVersion) external onlyOwner {
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();
        config.minValidatorVersion = newVersion;
        emit ConfigChanged();
    }

    /**
     * @notice Gets the minimum stake amount required for validator registration
     * @return The minimum stake amount in wei
     */
    function getMinStakeAmount() external view returns (uint256) {
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();
        return config.minStakeAmount;
    }

    /**
     * @notice Sets the minimum stake amount required for validator registration (owner only)
     * @param amount The new minimum stake amount in wei
     */
    function setMinStakeAmount(uint256 amount) external onlyOwner {
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();
        config.minStakeAmount = amount;
        emit ConfigChanged();
    }

    /**
     * @notice Sets the validation request fee amount
     * @param amount The new validation request fee in wei
     */
    function setValidationRequestAmount(uint256 amount) external {
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();
        config.validationRequestAmount = amount;
        emit ConfigChanged();
    }

    /**
     * @notice Gets the validation request fee amount
     * @return The validation request fee in wei
     */
    function getValidationRequestAmount() external view returns (uint256) {
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();
        return config.validationRequestAmount;
    }

    /////////////////////////////////
    // Validator Management
    /////////////////////////////////

    /**
     * @notice Gets the software version of a validator
     * @param validator The validator address
     * @return The validator's software version
     */
    function getValidatorVersion(address validator) external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        return state.validators[validator].version;
    }

    /**
     * @notice Sets the validator's software version
     * @param newVersion The new version number
     * @dev Version must be at least minValidatorVersion
     */
    function setValidatorVersion(uint256 newVersion) external {
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();

        if (newVersion < config.minValidatorVersion) {
            revert OpenStoreError(ERROR_VALIDATOR_UNSUPPORTED_VERSION);
        }

        state.validators[msg.sender].version = newVersion;
    }

    /**
     * @notice Gets the staked balance of a validator
     * @param validator The validator address
     * @return The validator's staked balance in wei
     */
    function getValidatorBalance(address validator) external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        uint256 balanceAndPower = state.validators[validator].balanceAndPower;
        return balanceAndPower.unpackBalance();
    }

    /**
     * @notice Deposits additional stake into validator's balance
     * @dev Increases balance and may reactivate validator if reaching minStakeAmount
     */
    function topUp() external payable {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();

        if (state.validators[sender].withdrawStatus > 0) {
            revert OpenStoreError(ERROR_VALIDATOR_IN_WITHDRAWAL);
        }

        uint256 balanceAndPower = state.validators[sender].balanceAndPower;
        uint128 balance = balanceAndPower.unpackBalance() + uint128(msg.value);
        uint128 power = balanceAndPower.unpackPower();

        if (balance > uint128(config.minStakeAmount)) {
            revert OpenStoreError(ERROR_INSUFFICIENT_STAKE);
        }
        
        state.validators[sender].balanceAndPower = BitPacking.packBalanceAndPower(balance, power);


        emit TopUp(sender, balance);
    }

    /**
     * @notice Initiates or completes withdrawal of validator's stake
     * @dev First call starts withdrawal timer, second call after WITHDRAWAL_PERIOD transfers funds
     */
    function withdraw() external payable {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();

        int256 time = state.validators[sender].withdrawStatus;
        if (time > 0) {
            if (int256(block.timestamp) - time < WITHDRAWAL_PERIOD) {
                revert OpenStoreError(ERROR_WITHDRAWAL_PERIOD_NOT_ELAPSED);
            }

            uint256 balanceAndPower = state.validators[sender].balanceAndPower;
            uint128 balance = balanceAndPower.unpackBalance();
            
            payable(msg.sender).transfer(balance);

            state.validators[sender].balanceAndPower = balanceAndPower.updateBalance(0);
            state.validators[sender].withdrawStatus = 0;

            emit Withdraw(sender, balance);
        } else {
            state.validators[sender].withdrawStatus = int256(block.timestamp);
            emit WithdrawStarted(sender);
        }
    }

    /////////////////////////////////
    // Request Management
    /////////////////////////////////

    /**
     * @return The next request ID user should create
     */
    function nextRequestIdToCreate() external view returns (uint256) {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        return state.nextRequestIdToCreate;
    }

    /**
     * @notice Creates a new validation request and sets its voting deadline
     * @param sender The request sender (must be target owner)
     * @param msgValue The amount sent with the request (must be >= validationRequestAmount)
     * @param reqType The type of validation request (1 = android_build)
     * @param target The target contract address
     * @param data Encoded request data
     * @return requestId The ID of the newly created request
     */
    function createRequest(
        address sender,
        uint256 msgValue,
        uint256 reqType,
        address target,
        bytes memory data
    ) external payable returns (uint256) {
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();
        if (config.isRequestsSuspended) {
            revert OpenStoreError(ERROR_REQUESTS_SUSPENDED);
        }
        
        if (msgValue < config.validationRequestAmount) {
            revert OpenStoreError(ERROR_INCORRECT_VALIDATION_FEE);
        }
        
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        if (sender != PluginOwnable(target).owner()) {
            revert OpenStoreError(ERROR_NOT_TARGET_OWNER);
        }

        if (reqType == 1) {// TODO to contract?
            uint256 _versionCode = data.toUint256(0);
            uint256 _ownerVersion = data.toUint256(32);
            uint256 _trackId = data.toUint256(64);
            if (_versionCode <= 0) {
                revert OpenStoreError(ERROR_BUILD_VERSION_ZERO);
            }

            if (_ownerVersion > 0) {
                uint256 _verifiedVersionId = IAssetlinksOracle(config.oracle)
                    .getLastVerifiedAssetVersion(target);

                if (_ownerVersion != _verifiedVersionId) {
                    revert OpenStoreError(ERROR_OWNER_NOT_VERIFIED);
                }
            }
        } else {
            revert OpenStoreError(ERROR_UNKNOWN_REQUEST_TYPE);
        }

        uint256 requestId = state.nextRequestIdToCreate;

        state.requests[requestId] = RequestInfo({
            reqType: reqType,
            target: target,
            data: data
        });

        state.requestVotingDeadline[requestId] = block.timestamp + VOTING_PERIOD;
        state.nextRequestIdToCreate = requestId + 1;

        return requestId;
    }

    //////////////////////
    // Voting Management
    //////////////////////

    /**
     * @notice Get validator's next request ID to vote on
     * @return The next request ID this validator should vote from
     */
    function nextValidatorRequestIdToVote() external view returns (uint256) {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        return state.validators[sender].nextRequestIdToVote;
    }

    /**
     * @notice Get the minimum request ID that can be voted on (global)
     * @return The minimum valid request ID for voting (earliest unexpired request)
     */
    function getGlobalRequestIdToVote() external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        return state.nextRequestIdToVote;
    }

    /**
     * @notice Get the valid voting range for a validator
     * @param validator The validator address
     * @return minReqId The minimum request ID (max of global min and validator's next)
     * @return maxReqId The maximum request ID (exclusive, nextRequestIdToCreate)
     */
    function getValidatorVotingRange(address validator) external view returns (uint256 minReqId, uint256 maxReqId) {
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();

        uint256 validatorNext = state.validators[validator].nextRequestIdToVote;
        uint256 globalMin = state.nextRequestIdToVote; // TODO

        minReqId = validatorNext > globalMin ? validatorNext : globalMin;
        maxReqId = state.nextRequestIdToCreate;
    }

    function getVotingState(uint256 requestId, uint8 status) external view returns (uint256) {
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        return state.votingState[requestId][status];
    }

    /**
     * @notice Submit votes for a range of validation requests
     * @param fromReqId Starting request ID (inclusive)
     * @param toReqId Ending request ID (exclusive)
     * @param result Packed voting results (8 bits per request, status code)
     * @dev Validator must be active, version compliant, and within valid range
     *      Gas-optimized with bit-packing: saves ~60% gas vs separate storage
     */
    function vote(uint256 fromReqId, uint256 toReqId, uint256 result) external {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();

        if ((toReqId - fromReqId) > 32) {
            revert OpenStoreError(ERROR_TOO_MANY_REQUESTS_IN_BLOCK);
        }

        if (state.validators[sender].withdrawStatus >= 0) {
            revert OpenStoreError(ERROR_VALIDATOR_IN_WITHDRAWAL);
        }

        if (state.validators[sender].version < config.minValidatorVersion) {
            revert OpenStoreError(ERROR_VALIDATOR_UNSUPPORTED_VERSION);
        }

        uint256 validatorNext = state.validators[sender].nextRequestIdToVote;
        if (fromReqId < validatorNext) {
            revert OpenStoreError(ERROR_INVALID_FROM_REQUEST_ID);
        }

        if (toReqId > state.nextRequestIdToCreate) {
            revert OpenStoreError(ERROR_INVALID_TO_REQUEST_ID);
        }

        uint256 votingDeadline = state.requestVotingDeadline[fromReqId];
        if (votingDeadline == 0 || block.timestamp > votingDeadline) {
            revert OpenStoreError(ERROR_VOTING_PERIOD_EXPIRED);
        }

        uint256 balanceAndPower = state.validators[sender].balanceAndPower;
        uint128 balance = balanceAndPower.unpackBalance();
        uint128 votePower = balanceAndPower.unpackPower();
        uint8 status;
        unchecked {
            for (uint256 i = fromReqId; i < toReqId; i++) {
                status = uint8(result >> ((i - fromReqId) * 8));
                
                uint256 statusData = state.votingState[i][status];
                uint128 currentTotalBalance = statusData.unpackBalance();
                uint128 currentTotalPower = statusData.unpackPower();

                uint128 newTotalBalance = currentTotalBalance + balance;
                uint128 newTotalPower = currentTotalPower + votePower;

                state.votingState[i][status] = BitPacking.packBalanceAndPower(newTotalBalance, newTotalPower);
                state.votes[i][msg.sender] = BitPacking.packVoteData(balance, uint120(votePower), status);

                uint8 oldStatusWinner = state.statusWinner[i];
                if (status != oldStatusWinner) {
                    uint256 oldWinnerData = state.votingState[i][oldStatusWinner];
                    uint128 oldWinnerBalance = oldWinnerData.unpackBalance();
                    if (newTotalBalance > oldWinnerBalance) {
                        state.statusWinner[i] = status;
                    }
                }
            }
        }

        state.validators[sender].nextRequestIdToVote = toReqId;
        emit Voted(sender, fromReqId, toReqId, result, votePower);
    }

    /**
     * @notice Claim rewards for finalized validation requests
     * @dev Processes all finalized requests since last claim
     *      Rewards include:
     *      - Balance: Proportional share of validation fee
     *      - Power: Voting power based on stake percentage (0.01% precision)
     *      Gas-efficient: Gets refunds from storage deletion (up to 20% on BSC)
     */
    function claim() external {
        address sender = msg.sender;
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();
        OpenStoreConfig storage config = OpenStoreStorageV2.openStoreConfig();

        advanceNextRequestIdToVote();

        uint256 lastClaimReqId = state.validators[sender].nextRequestIdToClaim;
        uint256 lastFinalizedReqId = state.nextRequestIdToVote;
        if (lastClaimReqId >= lastFinalizedReqId) {
            revert OpenStoreError(ERROR_NO_REWARDS_TO_CLAIM);
        }

        uint256 totalRewardBalance = 0;
        uint256 totalRewardPower = 0;

        unchecked {
            for (uint256 i = lastClaimReqId; i < lastFinalizedReqId; i++) {
                uint8 winningStatus = state.statusWinner[i];
                uint256 statusData = state.votingState[i][winningStatus];
                uint128 totalVotingBalance = statusData.unpackBalance();

                uint256 voteData = state.votes[i][msg.sender];
                uint8 validatorStatus = voteData.unpackVoteStatus();
                uint128 validatorBalance = voteData.unpackVoteBalance();
                
                if (validatorStatus == winningStatus && totalVotingBalance > 0) {
                    uint256 rewardBalance = (uint256(validatorBalance) * config.validationRequestAmount) / totalVotingBalance;
                    totalRewardBalance += rewardBalance;
                    
                    uint256 rewardPower = (uint256(validatorBalance) * BP_PERCENT) / totalVotingBalance;
                    totalRewardPower += rewardPower;

                    delete state.votes[i][msg.sender];
                }
            }
        }

        if (totalRewardBalance > 0 || totalRewardPower > 0) {
            uint256 balanceAndPower = state.validators[msg.sender].balanceAndPower;
            uint128 currentBalance = balanceAndPower.unpackBalance();
            uint128 currentPower = balanceAndPower.unpackPower();
            
            uint128 newBalance = currentBalance + uint128(totalRewardBalance);
            uint128 newPower = currentPower + uint128(totalRewardPower);
            
            state.validators[msg.sender].balanceAndPower = BitPacking.packBalanceAndPower(newBalance, newPower);

            emit Claimed(sender, newBalance, newPower);
        }

        state.validators[msg.sender].nextRequestIdToClaim = lastFinalizedReqId;
    }

    /**
     * @return advanced Number of requests advanced
     */
    function advanceNextRequestIdToVote() public returns (uint256 advanced) { // TODO
        OpenStoreState storage state = OpenStoreStorageV2.openStoreState();

        uint256 left = state.nextRequestIdToVote;
        uint256 right = state.nextRequestIdToCreate;

        if (left >= right) {
            return 0;
        }

        uint256 firstDeadline = state.requestVotingDeadline[left];
        if (firstDeadline > 0 && block.timestamp <= firstDeadline) {
            return 0;
        }

        unchecked {
            while (left < right) {
                uint256 mid = left + (right - left) / 2;
                uint256 deadline = state.requestVotingDeadline[mid];

                if (deadline == 0 || block.timestamp > deadline) {
                    left = mid + 1;
                } else {
                    right = mid;
                }
            }
        }

        advanced = left - state.nextRequestIdToVote;

        if (advanced > 0) {
            state.nextRequestIdToVote = left;
        }

        return advanced;
    }

    /**
     * @notice Finalizes expired requests and advances nextRequestIdToVote
     * @dev Can be called by anyone to advance the global request pointer
     *      Uses binary search - O(log n) complexity, very gas efficient
     * @return finalized Number of requests finalized
     */
    function finalizeExpiredRequests() external returns (uint256 finalized) {
        return advanceNextRequestIdToVote();
    }
}
