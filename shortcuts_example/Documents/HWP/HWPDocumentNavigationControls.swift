import SwiftUI

struct HWPDocumentNavigationControls: View {
    @ObservedObject var navigation: HWPDocumentNavigation
    var showsSearchButton = true
    let finishEditing: () -> Void
    @State private var showsPageJump = false
    @State private var pageText = ""

    var body: some View {
        HStack(spacing: 2) {
            if showsSearchButton {
                HWPDocumentFindButton(navigation: navigation, finishEditing: finishEditing)
            }

            Button("이전 쪽", systemImage: "chevron.left") { goToPage(navigation.currentPageIndex - 1) }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(navigation.currentPageIndex == 0)
            Button {
                finishEditing()
                pageText = String(navigation.currentPageIndex + 1)
                showsPageJump = true
            } label: {
                Text("\(navigation.currentPageIndex + 1) / \(max(1, navigation.pages.count))")
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("쪽 이동")
            .accessibilityValue(AppLocalization.format("%lld / %lld쪽",
                navigation.currentPageIndex + 1, navigation.pages.count))
            .accessibilityIdentifier("hwp-page-jump")
            Button("다음 쪽", systemImage: "chevron.right") { goToPage(navigation.currentPageIndex + 1) }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(navigation.currentPageIndex >= navigation.pages.count - 1)

            Menu {
                Button("화면 폭에 맞추기") { navigation.setZoom(nil) }
                ForEach([50, 75, 100, 150, 200, 300, 400], id: \.self) { percent in
                    Button("\(percent)%") { navigation.setZoom(CGFloat(percent) / 100) }
                }
            } label: {
                Text("\(Int((navigation.zoomScale * 100).rounded()))%")
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: 52, minHeight: 44)
            }
            .accessibilityLabel("확대·축소")
            .accessibilityValue("\(Int((navigation.zoomScale * 100).rounded()))%")
            .accessibilityIdentifier("hwp-zoom-menu")
        }
        .font(.subheadline)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(navigation.pages.isEmpty)
        .sheet(isPresented: $showsPageJump) {
            NavigationStack {
                Form {
                    TextField("쪽 번호", text: $pageText)
                        .keyboardType(.numberPad)
                        .onSubmit(jump)
                        .accessibilityIdentifier("hwp-page-number")
                    Text(AppLocalization.format("1~%lld쪽 사이의 번호를 입력하세요.", navigation.pages.count))
                        .foregroundStyle(.secondary)
                }
                .navigationTitle("쪽 이동")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { showsPageJump = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("이동", action: jump)
                            .disabled(navigation.pageNumber(from: pageText) == nil)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func goToPage(_ index: Int) {
        finishEditing()
        navigation.goToPage(index)
    }

    private func jump() {
        guard let page = navigation.pageNumber(from: pageText) else { return }
        navigation.goToPage(page - 1)
        showsPageJump = false
    }
}

struct HWPDocumentFindButton: View {
    @ObservedObject var navigation: HWPDocumentNavigation
    let finishEditing: () -> Void
    var body: some View {
        Button("찾기·바꾸기", systemImage: "magnifyingglass") {
            finishEditing()
            if navigation.showsSearch { navigation.closeSearch() }
            else { navigation.showsSearch = true }
        }
        .keyboardShortcut("f", modifiers: .command)
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .accessibilityIdentifier("hwp-search-toggle")
        .frame(width: 44, height: 44)
        .background(navigation.showsSearch ? Color.accentColor.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 10))
    }
}

struct HWPDocumentSearchBar: View {
    @ObservedObject var navigation: HWPDocumentNavigation
    var allowsReplacement = false
    var finishEditing: () -> Void = {}
    var onReplace: ((Bool) -> Void)? = nil
    @FocusState private var focusedField: Field?
    private enum Field { case query, replacement }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                TextField("찾을 내용", text: $navigation.query)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focusedField, equals: .query)
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("hwp-search-field")
                Menu {
                    Toggle("대소문자 구분", isOn: $navigation.matchCase)
                } label: {
                    Image(systemName: "textformat.abc")
                        .foregroundStyle(navigation.matchCase ? Color.accentColor : .primary)
                }
                .accessibilityLabel("검색 옵션")
                .accessibilityIdentifier("hwp-search-options")
                Button("이전 검색 결과", systemImage: "chevron.up") { move(by: -1) }
                    .disabled(navigation.results.isEmpty)
                    .accessibilityIdentifier("hwp-search-previous")
                Button("다음 검색 결과", systemImage: "chevron.down") { move(by: 1) }
                    .disabled(navigation.results.isEmpty)
                    .accessibilityIdentifier("hwp-search-next")
                Button("검색 닫기", systemImage: "xmark") {
                    focusedField = nil
                    navigation.closeSearch()
                }
                .accessibilityIdentifier("hwp-search-close")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(HWPSearchButtonStyle())
            HStack(spacing: 8) {
                if allowsReplacement {
                    Button {
                        navigation.showsReplacement.toggle()
                    } label: {
                        Label("바꾸기", systemImage: navigation.showsReplacement ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hwp-replace-toggle")
                    .frame(minHeight: 32)
                }
                if let result = navigation.selectedResult {
                    Text(AppLocalization.format("검색 결과 %lld / %lld · %lld쪽",
                        navigation.selectedResultIndex + 1, navigation.results.count, result.pageIndex + 1))
                        .accessibilityIdentifier("hwp-search-count")
                } else if !navigation.query.isEmpty {
                    Text("검색 결과가 없습니다.").accessibilityIdentifier("hwp-search-count")
                } else {
                    Text("본문과 표에서 찾습니다.")
                }
                Spacer(minLength: 0)
            }
            .font(.caption).foregroundStyle(.secondary)
            if allowsReplacement, navigation.showsReplacement {
                HStack(spacing: 8) {
                    TextField("바꿀 내용", text: $navigation.replacement)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .replacement)
                        .onSubmit { focusedField = nil }
                        .accessibilityIdentifier("hwp-replace-field")
                    Button("바꾸기") { replace(all: false) }
                        .disabled(navigation.selectedResult?.match.isReplaceable != true)
                        .accessibilityIdentifier("hwp-replace-one")
                    Button("모두 바꾸기") { replace(all: true) }
                        .disabled(navigation.exceedsSearchLimit || !navigation.results.contains { $0.match.isReplaceable })
                        .accessibilityIdentifier("hwp-replace-all")
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
            if navigation.exceedsSearchLimit {
                Text(HWPFindReplaceError.tooManyMatches.localizedDescription).font(.caption).foregroundStyle(.secondary)
            } else if let message = navigation.replacementMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("hwp-replace-message")
            } else if let result = navigation.selectedResult {
                Text(result.snippet).font(.caption).lineLimit(2)
                    .accessibilityIdentifier("hwp-search-snippet")
                if navigation.showsReplacement, !result.match.isReplaceable {
                    Text("이 검색 결과는 편집할 수 없습니다.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(VisionCraftUI.surface)
        .task { focusedField = .query }
        .onChange(of: focusedField) { _, field in if field != nil { finishEditing() } }
    }

    private func replace(all: Bool) {
        focusedField = nil
        onReplace?(all)
    }

    private func move(by offset: Int) {
        focusedField = nil
        finishEditing()
        navigation.moveResult(by: offset)
    }
}

private struct HWPSearchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
