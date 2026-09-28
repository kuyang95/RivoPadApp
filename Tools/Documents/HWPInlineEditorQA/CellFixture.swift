import Foundation

enum InlineQACellFixture {
    static var tableXML: String {
        let rows = (0..<2).map { row in
            let cells = (0..<2).map { column in
                let texts = row == 0 && column == 0 ? ["첫 문단", "둘째 문단"] : ["다른 셀"]
                let paragraphs = texts.enumerated().map { i, text in
                    "<hp:p id=\"\(10 + row * 10 + column * 2 + i)\" paraPrIDRef=\"0\" styleIDRef=\"0\"><hp:run charPrIDRef=\"0\"><hp:t>\(text)</hp:t></hp:run></hp:p>"
                }.joined()
                return "<hp:tc borderFillIDRef=\"0\" hasMargin=\"1\"><hp:subList vertAlign=\"TOP\">\(paragraphs)</hp:subList><hp:cellAddr colAddr=\"\(column)\" rowAddr=\"\(row)\"/><hp:cellSpan colSpan=\"1\" rowSpan=\"1\"/><hp:cellSz width=\"12000\" height=\"9000\"/><hp:cellMargin left=\"400\" right=\"400\" top=\"400\" bottom=\"400\"/></hp:tc>"
            }.joined()
            return "<hp:tr>\(cells)</hp:tr>"
        }.joined()
        return "<hp:tbl id=\"9\" rowCnt=\"2\" colCnt=\"2\" borderFillIDRef=\"0\" pageBreak=\"CELL\"><hp:sz width=\"24000\" height=\"18000\"/><hp:pos treatAsChar=\"1\"/>\(rows)</hp:tbl>"
    }

}
