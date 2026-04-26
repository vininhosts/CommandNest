import SwiftUI

struct ModelPickerView: View {
    @Binding var selectedModel: String
    let models: [String]
    @State private var isPickerPresented = false
    @State private var searchText = ""

    var body: some View {
        Button {
            searchText = ""
            isPickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedModel.isEmpty ? "Select model" : selectedModel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 220)
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search models", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredModels, id: \.self) { model in
                            Button {
                                selectedModel = model
                                isPickerPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: selectedModel == model ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedModel == model ? Color.accentColor : Color.secondary.opacity(0.45))

                                    Text(model)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(selectedModel == model ? Color.accentColor.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }

                        if filteredModels.isEmpty {
                            Text("No matching models")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 280)
            }
            .padding(12)
            .frame(width: 430)
        }
        .accessibilityLabel("Model")
    }

    private var filteredModels: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return models
        }

        return models.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}
