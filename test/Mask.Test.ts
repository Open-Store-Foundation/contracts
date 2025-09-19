import {
    applyUnavailabilityToResult,
    compareResultsExcludingUnavailable,
    createUnavailabilityMask,
    shouldSlashDiscussionProposal
} from "./utils/mask";
import {expect} from "chai";

describe("Helper Functions - Unavailability Logic", function () {
    describe("createUnavailabilityMask", function () {
        it("should create correct mask for single unavailable request", function () {
            const mask = createUnavailabilityMask(4, [0]);
            expect(mask).to.equal(0b0001);
        });

        it("should create correct mask for multiple unavailable requests", function () {
            const mask = createUnavailabilityMask(4, [0, 2]);
            expect(mask).to.equal(0b0101);
        });

        it("should create correct mask for consecutive unavailable requests", function () {
            const mask = createUnavailabilityMask(4, [0, 1]);
            expect(mask).to.equal(0b0011);
        });

        it("should handle empty unavailable requests", function () {
            const mask = createUnavailabilityMask(4, []);
            expect(mask).to.equal(0b0000);
        });

        it("should ignore out-of-bounds request indices", function () {
            const mask = createUnavailabilityMask(4, [0, 1, 5, 10]);
            expect(mask).to.equal(0b0011);
        });
    });

    describe("applyUnavailabilityToResult", function () {
        it("should change unavailable requests to status 00", function () {
            const result = 0b01010101;
            const mask = 0b1100;
            const finalResult = applyUnavailabilityToResult(result, mask, 4);
            expect(finalResult).to.equal(0b00000101);
        });

        it("should preserve available requests", function () {
            const result = 0b11100101;
            const mask = 0b0001;
            const finalResult = applyUnavailabilityToResult(result, mask, 4);
            expect(finalResult).to.equal(0b11100100);
        });

        it("should handle no unavailable requests", function () {
            const result = 0b01010101;
            const mask = 0b0000;
            const finalResult = applyUnavailabilityToResult(result, mask, 4);
            expect(finalResult).to.equal(0b01010101);
        });

        it("should handle all requests unavailable", function () {
            const result = 0b11100111;
            const mask = 0b1111;
            const finalResult = applyUnavailabilityToResult(result, mask, 4);
            expect(finalResult).to.equal(0b00000000);
        });
    });

    describe("compareResultsExcludingUnavailable", function () {
        it("should return true for identical results", function () {
            const result1 = 0b01010101;
            const result2 = 0b01010101;
            const mask = 0b1100;
            const isEqual = compareResultsExcludingUnavailable(result1, result2, mask, 4);
            expect(isEqual).to.be.true;
        });

        it("should return true when differences are only in unavailable positions", function () {
            const result1 = 0b01010101;
            const result2 = 0b11110101;
            const mask = 0b1100;
            const isEqual = compareResultsExcludingUnavailable(result1, result2, mask, 4);
            expect(isEqual).to.be.true;
        });

        it("should return false when differences exist in available positions", function () {
            const result1 = 0b01010101;
            const result2 = 0b01011101;
            const mask = 0b1100;
            const isEqual = compareResultsExcludingUnavailable(result1, result2, mask, 4);
            expect(isEqual).to.be.false;
        });

        it("should return false for completely different results", function () {
            const result1 = 0b01010101;
            const result2 = 0b11111111;
            const mask = 0b0000;
            const isEqual = compareResultsExcludingUnavailable(result1, result2, mask, 4);
            expect(isEqual).to.be.false;
        });
    });

    describe("shouldSlashDiscussionProposal", function () {
        it("should slash when discussion differs from winner in available positions", function () {
            const winnerResult = 0b01010101;
            const discussionResult = 0b01011101;
            const mask = 0b1100;
            const shouldSlash = shouldSlashDiscussionProposal(winnerResult, discussionResult, mask, 4);
            expect(shouldSlash).to.be.true;
        });

        it("should not slash when discussion only differs in unavailable positions", function () {
            const winnerResult = 0b01010101;
            const discussionResult = 0b11110101;
            const mask = 0b1100;
            const shouldSlash = shouldSlashDiscussionProposal(winnerResult, discussionResult, mask, 4);
            expect(shouldSlash).to.be.false;
        });

        it("should not slash when discussion matches winner exactly", function () {
            const winnerResult = 0b01010101;
            const discussionResult = 0b01010101;
            const mask = 0b1100;
            const shouldSlash = shouldSlashDiscussionProposal(winnerResult, discussionResult, mask, 4);
            expect(shouldSlash).to.be.false;
        });

        it("should handle complex mixed scenarios", function () {
            const winnerResult = 0b11010110;
            const discussionResult = 0b11111111;
            const mask = 0b1001;
            const shouldSlash = shouldSlashDiscussionProposal(winnerResult, discussionResult, mask, 4);
            expect(shouldSlash).to.be.true;
        });
    });

    describe("demonstrateSlashingLogic - Your Example", function () {
        it("should verify step by step breakdown", function () {
            const requestCount = 4;
            const winnerResult = 0b01010101;
            const discussion1Result = 0b01011101;
            const discussion2Result = 0b01110101;
            const unavailabilityMask = 0b1100;

            const finalWinnerResult = applyUnavailabilityToResult(winnerResult, unavailabilityMask, requestCount);
            expect(finalWinnerResult).to.equal(0b00000101);

            const discussion1MatchesWinner = compareResultsExcludingUnavailable(
                finalWinnerResult, discussion1Result, unavailabilityMask, requestCount
            );
            expect(discussion1MatchesWinner).to.be.false;

            const discussion2MatchesWinner = compareResultsExcludingUnavailable(
                finalWinnerResult, discussion2Result, unavailabilityMask, requestCount
            );
            expect(discussion2MatchesWinner).to.be.true;
        });
    });

    describe("Edge Cases", function () {
        it("should handle single request scenarios", function () {
            const winnerResult = 0b01;
            const discussionResult = 0b11;
            const mask = 0b0;
            const shouldSlash = shouldSlashDiscussionProposal(winnerResult, discussionResult, mask, 1);
            expect(shouldSlash).to.be.true;
        });

        it("should handle single request made unavailable", function () {
            const winnerResult = 0b01;
            const discussionResult = 0b11;
            const mask = 0b1;
            const shouldSlash = shouldSlashDiscussionProposal(winnerResult, discussionResult, mask, 1);
            expect(shouldSlash).to.be.false;
        });

        it("should handle maximum requests (128)", function () {
            const requestCount = 128;
            const mask = createUnavailabilityMask(requestCount, [0, 1, 126, 127]);
            expect(mask & 0b1).to.equal(1);
            expect((mask >> 1) & 0b1).to.equal(1);
            expect((mask >> 126) & 0b1).to.equal(1);
            expect((mask >> 127) & 0b1).to.equal(1);
        });
    });
});
