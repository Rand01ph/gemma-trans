import SwiftUI

struct MainView: View {
    let controller: EngineController

    @State private var input = ""
    @State private var viewModel = TranslationViewModel()

    private var canTranslate: Bool {
        controller.engineStatus == .ready
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            GTContentBackground()
            TranslationWorkspace(controller: controller,
                                 input: $input,
                                 viewModel: viewModel,
                                 canTranslate: canTranslate,
                                 translate: translate,
                                 clearInput: clearInput)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .gtApplicationAppearance()
    }

    private func translate() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, controller.engineStatus == .ready, let engine = controller.engine else { return }
        viewModel.reset()
        viewModel.start(text: text, engine: engine)
    }

    private func clearInput() {
        input = ""
    }
}
