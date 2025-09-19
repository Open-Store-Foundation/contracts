
export interface GfContracts {
    executor: string
    permissionHub: string
    tokenHub: string
    bucketHub: string
    crossChain: string
}

export interface StoreConfig {
    version: number;
    minValidatorVersion: number;
    isRequestsSuspended: boolean;
    isQueueSuspended: boolean;
    maxParallelProposals: number;
    maxInactiveBlocks: number;
    maxReqPerBlock: number;
    validationRequestAmount: bigint;
    baseProposalAmount: bigint;
    baseVoteAmount: bigint;
    overdueProposalFee: bigint;
    inactiveFee: bigint;
    minStakeAmount: bigint;
    basicAmount: bigint;
    proposalBlockWindow: number;
    voteBlockWindow: number;
    minFinalizationWindow: number
}