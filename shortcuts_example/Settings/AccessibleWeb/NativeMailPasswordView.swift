import SwiftUI

/// Secure text remains in view memory only and is cleared on submit, hiding or cancellation.
@MainActor
struct NativeMailPasswordView: View {
    @ObservedObject var browser: AccessibleWebBrowserModel
    let onEditAddress: () -> Void
    @State private var password = ""
    @State private var reveal = false
    @State private var missing = false
    @FocusState private var editing: Bool
    private var theme: RatioExperience { AccessibleWebTheme.colors }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("비밀번호를\n입력해 주세요").visionCraftAndroidText(36, weight: .medium, relativeTo: .largeTitle)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader).padding(.top, 16)
                    HStack(spacing: 8) {
                        Group {
                            if reveal { TextField("비밀번호", text: $password) }
                            else { SecureField("비밀번호", text: $password) }
                        }
                        .visionCraftAndroidText(22).textContentType(.password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        .focused($editing).submitLabel(.go).onSubmit(submit)
                        Button { reveal.toggle() } label: {
                            Image(systemName: reveal ? "eye.slash" : "eye").font(.title3).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(reveal ? Text("비밀번호 숨기기") : Text("비밀번호 보기"))
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 76)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(missing || browser.mailLoginError != nil ? VisionCraftUI.fixedColor(0xFFB4AB) : editing ? theme.accent : theme.text.opacity(0.5), lineWidth: editing ? 2 : 1))
                    .padding(.top, 28)
                    if missing { Text("비밀번호를 입력해 주세요").visionCraftAndroidText(17).foregroundStyle(VisionCraftUI.fixedColor(0xFFB4AB)).padding(.top, 12) }
                    else if let error = browser.mailLoginError { Text(verbatim: error).visionCraftAndroidText(17).foregroundStyle(VisionCraftUI.fixedColor(0xFFB4AB)).padding(.top, 12) }
                    Button(action: submit) {
                        HStack {
                            Text("로그인").visionCraftAndroidText(22, weight: .semibold)
                            Spacer(); Image(systemName: "arrow.right").font(.title2).accessibilityHidden(true)
                        }
                        .foregroundStyle(theme.text).padding(.horizontal, 24).padding(.vertical, 18)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(theme.magnifier, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(theme.text).allowsHitTesting(false))
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }.buttonStyle(.plain).padding(.top, 18)
                    if browser.mailLoginError != nil {
                        Button("주소 수정", action: onEditAddress).frame(minHeight: 52)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, 28).padding(.vertical, 40).frame(minHeight: geometry.size.height)
            }.scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(theme.text).tint(theme.accent)
        .onChange(of: password) { _, _ in missing = false }
        .onChange(of: editing) { _, value in browser.mailEntryEditing = value }
        .onChange(of: browser.youtubeContentActive) { _, active in
            if !active { password = ""; reveal = false; editing = false }
        }
        .onDisappear { password = ""; browser.mailEntryEditing = false }
    }
    private func submit() {
        guard !password.isEmpty else { missing = true; return }
        let input = password; password = ""; reveal = false; editing = false
        browser.signInMail(password: input)
    }
}

@MainActor
struct NativeMailLoadingView: View {
    let onCancel: () -> Void
    private var theme: RatioExperience { AccessibleWebTheme.colors }
    var body: some View {
        VStack(spacing: 24) {
            Text("메일을 여는 중").visionCraftAndroidText(24).accessibilityAddTraits(.isHeader)
            ProgressView().progressViewStyle(.linear).tint(theme.accent).frame(maxWidth: 280)
            Button("취소", action: onCancel).visionCraftAndroidText(18).frame(minHeight: 52)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        .foregroundStyle(theme.text).tint(theme.accent)
    }
}
