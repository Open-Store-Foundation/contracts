import {BLOCK_RESULT_STATUS} from "./const";
import {BigNumberish} from "ethers";

export function createResultMask(requestCount: BigNumberish, statuses?: number[]): number {
    let result = 0;
    let count = Number(requestCount.toString());
    for (let i = 0; i < count; i++) {
        const status = statuses?.[i] ?? BLOCK_RESULT_STATUS.SUCCESS;
        result |= (status << (i * 2));
    }
    return result;
}

export function createUnavailabilityMask(requestCount: number, unavailableRequests: number[]): number {
    let mask = 0;
    for (const requestIndex of unavailableRequests) {
        if (requestIndex < requestCount) {
            mask |= (1 << requestIndex);
        }
    }
    return mask;
}

export function applyUnavailabilityToResult(result: number, unavailabilityMask: number, requestCount: number): number {
    let finalResult = result;
    for (let i = 0; i < requestCount; i++) {
        if ((unavailabilityMask >> i) & 1) {
            const bitPosition = i * 2;
            finalResult &= ~(3 << bitPosition);
        }
    }
    return finalResult;
}

export function compareResultsExcludingUnavailable(result1: number, result2: number, unavailabilityMask: number, requestCount: number): boolean {
    for (let i = 0; i < requestCount; i++) {
        if ((unavailabilityMask >> i) & 1) {
            continue;
        }

        const bitPosition = i * 2;
        const status1 = (result1 >> bitPosition) & 3;
        const status2 = (result2 >> bitPosition) & 3;

        if (status1 !== status2) {
            return false;
        }
    }
    return true;
}

export function shouldSlashDiscussionProposal(
    winnerResult: number,
    discussionResult: number,
    unavailabilityMask: number,
    requestCount: number
): boolean {
    const finalWinnerResult = applyUnavailabilityToResult(winnerResult, unavailabilityMask, requestCount);
    return !compareResultsExcludingUnavailable(finalWinnerResult, discussionResult, unavailabilityMask, requestCount);
}
