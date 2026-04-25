import SwiftUI

struct ModelPickerView: View {
    @Binding var selectedModel: String
    let models: [String]

    var body: some View {
        Picker("Model", selection: $selectedModel) {
            ForEach(models, id: \.self) { model in
                Text(model).tag(model)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 190)
        .accessibilityLabel("Model")
    }
}
