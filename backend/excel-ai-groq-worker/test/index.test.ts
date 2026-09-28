import { describe, expect, it } from "vitest";
import { buildGroqRequest, isValidPlan, isValidRequest } from "../src/index";

const validRequest = {
  userRequest: "김하늘 학생 행을 추가해 줘",
  recentConversation: [],
  worksheet: {
    workbookName: "코덱스초등학교.xlsx",
    sheetName: "1학년 5반",
    sheetPartPath: "xl/worksheets/sheet1.xml",
    selectedCell: null,
    regions: [],
    mergedRanges: ["A1:E1"],
    cells: [],
    contextWasTruncated: false,
    revision: "abc123",
  },
};

describe("Excel AI request validation", () => {
  it("accepts the app request shape", () => {
    expect(isValidRequest(validRequest)).toBe(true);
  });

  it("rejects more conversation turns than the app sends", () => {
    const request = {
      ...validRequest,
      recentConversation: Array.from({ length: 9 }, () => ({
        role: "user",
        text: "계속",
      })),
    };
    expect(isValidRequest(request)).toBe(false);
  });
});

describe("Groq structured output contract", () => {
  it("uses GPT-OSS 20B with strict JSON schema output", () => {
    const body = buildGroqRequest(validRequest) as Record<string, unknown>;
    expect(body.model).toBe("openai/gpt-oss-20b");
    expect(body.reasoning_effort).toBe("low");
    expect(body.reasoning_format).toBe("hidden");
    expect(body.response_format).toMatchObject({
      type: "json_schema",
      json_schema: { strict: true },
    });
  });

  it("accepts a bounded edit plan", () => {
    expect(
      isValidPlan({
        intent: "edit",
        assistantMessage: "한 행을 추가할게요.",
        edits: [],
        appendedRows: [
          {
            regionID: "region-1",
            values: [{ column: 1, newValue: "김하늘" }],
          },
        ],
      }),
    ).toBe(true);
  });

  it("rejects changes hidden inside an answer", () => {
    expect(
      isValidPlan({
        intent: "answer",
        assistantMessage: "완료했습니다.",
        edits: [{ row: 2, column: 1, newValue: "김하늘" }],
        appendedRows: [],
      }),
    ).toBe(false);
  });
});
