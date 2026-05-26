import SwiftUI

struct TerminalAccessoryCustomizationView: View {
    @EnvironmentObject private var preferences: TerminalAccessoryPreferencesManager
    @State private var showingCreateActionSheet = false

    private var activeItems: [TerminalAccessoryItemRef] {
        preferences.activeItems
    }

    private var activeRows: [[TerminalAccessoryItemRef]] {
        preferences.activeRows
    }

    private var activeSystemActions: Set<TerminalAccessorySystemActionID> {
        Set(activeItems.compactMap { item in
            if case .system(let actionID) = item {
                return actionID
            }
            return nil
        })
    }

    private var activeCustomActionIDs: Set<UUID> {
        Set(activeItems.compactMap { item in
            if case .custom(let id) = item {
                return id
            }
            return nil
        })
    }

    private var availableSystemActions: [TerminalAccessorySystemActionID] {
        TerminalAccessoryProfile.availableSystemActions
            .filter { !activeSystemActions.contains($0) }
    }

    private var availableCustomActions: [TerminalAccessoryCustomAction] {
        preferences.customActions.filter { !activeCustomActionIDs.contains($0.id) }
    }

    private var hasAnyCustomActions: Bool {
        !preferences.customActions.isEmpty
    }

    private var activeCustomActionsByID: [UUID: TerminalAccessoryCustomAction] {
        Dictionary(uniqueKeysWithValues: preferences.customActions.map { ($0.id, $0) })
    }

    var body: some View {
        Form {
            Section("Preview") {
                VStack(spacing: 6) {
                    ForEach(0..<TerminalAccessoryProfile.rowCount, id: \.self) { rowIndex in
                        HStack(spacing: 6) {
                            ForEach(0..<TerminalAccessoryProfile.itemsPerRow, id: \.self) { columnIndex in
                                if let item = item(atRow: rowIndex, column: columnIndex) {
                                    previewChip(label(for: item))
                                        .frame(maxWidth: .infinity)
                                } else {
                                    emptyPreviewChip()
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(0..<TerminalAccessoryProfile.rowCount, id: \.self) { rowIndex in
                Section {
                    let row = activeRow(at: rowIndex)
                    if row.isEmpty {
                        Text("No items")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(row.enumerated()), id: \.element) { _, item in
                            HStack(spacing: 10) {
                                Text(label(for: item))
                                Spacer(minLength: 8)
                                if let detail = detailLabel(for: item) {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            preferences.removeActiveItems(inRow: rowIndex, atOffsets: offsets)
                        }
                        .onMove { offsets, destination in
                            preferences.moveActiveItems(inRow: rowIndex, fromOffsets: offsets, toOffset: destination)
                        }
                    }
                } header: {
                    Text(rowTitle(rowIndex))
                } footer: {
                    Text(
                        String(
                            format: String(localized: "%lld/%lld items"),
                            Int64(activeRow(at: rowIndex).count),
                            Int64(TerminalAccessoryProfile.itemsPerRow)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Available System Actions") {
                if availableSystemActions.isEmpty {
                    Text("All system actions are already added.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableSystemActions) { actionID in
                        HStack {
                            Text(actionID.listTitle)
                            Spacer(minLength: 8)
                            rowAddButtons(for: .system(actionID))
                        }
                    }
                }
            }

            Section {
                if availableCustomActions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            hasAnyCustomActions
                                ? String(localized: "All custom actions are already added.")
                                : String(localized: "No custom actions yet.")
                        )
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(availableCustomActions) { action in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(action.title)
                                Text(action.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            rowAddButtons(for: .custom(action.id))
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Available Custom Actions")
                    Spacer(minLength: 8)
                    Button {
                        showingCreateActionSheet = true
                    } label: {
                        Label("Create Action", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!preferences.canCreateCustomAction)
                }
            }

            Section {
                Button("Reset to Default") {
                    preferences.resetToDefaultLayout()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Customize Accessory Bar")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        #endif
        .sheet(isPresented: $showingCreateActionSheet) {
            TerminalCustomActionFormView()
        }
    }

    @ViewBuilder
    private func previewChip(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }

    @ViewBuilder
    private func emptyPreviewChip() -> some View {
        Text(" ")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rowAddButtons(for item: TerminalAccessoryItemRef) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<TerminalAccessoryProfile.rowCount, id: \.self) { rowIndex in
                Button(rowTitle(rowIndex)) {
                    preferences.addActiveItem(item, toRow: rowIndex)
                }
                .buttonStyle(.borderless)
                .disabled(activeItems.contains(item) || rowIsFull(rowIndex))
            }
        }
    }

    private func rowTitle(_ rowIndex: Int) -> String {
        String(format: String(localized: "Row %lld"), Int64(rowIndex + 1))
    }

    private func activeRow(at rowIndex: Int) -> [TerminalAccessoryItemRef] {
        guard activeRows.indices.contains(rowIndex) else { return [] }
        return activeRows[rowIndex]
    }

    private func item(atRow rowIndex: Int, column columnIndex: Int) -> TerminalAccessoryItemRef? {
        let row = activeRow(at: rowIndex)
        guard row.indices.contains(columnIndex) else { return nil }
        return row[columnIndex]
    }

    private func rowIsFull(_ rowIndex: Int) -> Bool {
        activeRow(at: rowIndex).count >= TerminalAccessoryProfile.itemsPerRow
    }

    private func label(for item: TerminalAccessoryItemRef) -> String {
        switch item {
        case .system(let actionID):
            return actionID.listTitle
        case .custom(let id):
            return activeCustomActionsByID[id]?.title ?? String(localized: "Custom Action")
        }
    }

    private func detailLabel(for item: TerminalAccessoryItemRef) -> String? {
        switch item {
        case .system:
            return nil
        case .custom(let id):
            return activeCustomActionsByID[id]?.kind.title
        }
    }
}
