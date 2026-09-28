import XCTest

@testable import shortcuts_example

final class ChatWebSearchRouterTests: XCTestCase {
    func testVolatileTopicsNeedTheLiveWeb() {
        let prompts = [
            "오늘 서울 날씨 어때?",
            "지금 환율 얼마야",
            "삼성전자 주가 알려줘",
            "속보 좀 요약해줘",
            "what is the weather in Seoul",
            "latest news about the election",
            "今日の天気は",
        ]
        for prompt in prompts {
            XCTAssertTrue(
                ChatWebSearchRouter
                    .requiresCurrentInformation(prompt),
                prompt
            )
        }
    }

    func testCurrentTimeWordNeedsALookupWord() {
        XCTAssertTrue(
            ChatWebSearchRouter.requiresCurrentInformation(
                "오늘 우리 동네 도서관 몇 시까지 열려?"
            )
        )
        // A time word on its own is not a web question.
        XCTAssertFalse(
            ChatWebSearchRouter.requiresCurrentInformation(
                "오늘 기분이 좀 이상한데 왜 그럴까?"
            )
        )
    }

    func testOrdinaryChatStaysLocal() {
        let prompts = [
            "이 문단을 더 쉽게 고쳐줘",
            "파이썬으로 이진 탐색 짜줘",
            "회의록 요약해줘",
            "explain how a diesel engine works",
            "내 이름은 무엇으로 기억하고 있어?",
            "",
            "   ",
        ]
        for prompt in prompts {
            XCTAssertFalse(
                ChatWebSearchRouter
                    .requiresCurrentInformation(prompt),
                prompt
            )
        }
    }
}
