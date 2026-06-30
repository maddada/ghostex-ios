//
//  SettingsView.swift
//  VVTerm
//

import SwiftUI
#if os(macOS)
import AppKit

private extension View {
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
#endif

// MARK: - Settings Selection

enum SettingsSelection: Hashable {
    case pro
    case general
    case terminal
    case transcription
    case keychain
    case sync
    case about
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage(TerminalDefaults.fontNameKey) private var terminalFontName = TerminalDefaults.defaultFontName
    @AppStorage(TerminalDefaults.fontSizeKey) private var terminalFontSize = TerminalDefaults.defaultFontSize

    @State private var selection: SettingsSelection? = .pro
    @StateObject private var storeManager = StoreManager.shared

    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                // Pro at top (not part of selection - has its own styling)
                Button {
                    selection = .pro
                } label: {
                    proNavigationRow
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Divider()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                settingsRow("General", icon: "gear", tag: .general)
                settingsRow("Terminal", icon: "terminal", tag: .terminal)
                settingsRow("Transcription", icon: "waveform", tag: .transcription)
                settingsRow("SSH Keys", icon: "key", tag: .keychain)
                settingsRow("Sync", icon: "icloud", tag: .sync)
                settingsRow("About", icon: "info.circle", tag: .about)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 240, maxHeight: .infinity)
            .navigationSplitViewColumnWidth(240)
            .removingSidebarToggle()
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 500)
        #else
        NavigationStack {
            /*
            CDXC:iOSSettingsBranding 2026-06-29-22:21:
            Ghostex iOS settings must not surface upstream VVTerm branding or the commercial/about entry points requested for removal. Keep the Pro and About rows out of the iPhone settings navigation while shared/internal VVTerm symbols remain unchanged.

            CDXC:iOSSettingsCredits 2026-06-30-04:37:
            Settings needs a bottom Credits entry that clearly gives full credit to the upstream VVTerm project and recommends supporting Vivy through VVTerm Premium or GitHub Sponsors.
            */
            List {
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                            .navigationTitle("General")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("General", systemImage: "gear")
                    }

                    NavigationLink {
                        TerminalSettingsView(fontName: $terminalFontName, fontSize: $terminalFontSize)
                            .navigationTitle("Terminal")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }

                    NavigationLink {
                        TranscriptionSettingsView()
                            .navigationTitle("Transcription")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("Transcription", systemImage: "waveform")
                    }

                    NavigationLink {
                        KeychainSettingsView()
                            .navigationTitle("SSH Keys")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("SSH Keys", systemImage: "key")
                    }

                    NavigationLink {
                        SyncSettingsView()
                            .navigationTitle("Sync")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("Sync", systemImage: "icloud")
                    }
                }

                Section {
                    NavigationLink {
                        GhostexCreditsView()
                            .navigationTitle("Credits")
                            .navigationBarTitleDisplayMode(.inline)
                            .adaptiveSoftScrollEdges()
                    } label: {
                        Label("Credits", systemImage: "heart")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .adaptiveSoftScrollEdges()
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .pro:
                            ProSettingsView()
                                .navigationTitle("Ghostex Pro")
                                .navigationSubtitle(storeManager.isPro
                                    ? String(localized: "Manage your subscription")
                                    : String(localized: "Upgrade for unlimited features")
                                )
        case .general:
                            GeneralSettingsView()
                                .navigationTitle("General")
                                .navigationSubtitle(String(localized: "Appearance and preferences"))
        case .terminal:
                            TerminalSettingsView(fontName: $terminalFontName, fontSize: $terminalFontSize)
                                .navigationTitle("Terminal")
                                .navigationSubtitle(String(localized: "Font, theme, and connection settings"))
        case .transcription:
                            TranscriptionSettingsView()
                                .navigationTitle("Transcription")
                                .navigationSubtitle(String(localized: "Speech-to-text engine and models"))
        case .keychain:
                            KeychainSettingsView()
                                .navigationTitle("SSH Keys")
                                .navigationSubtitle(String(localized: "Manage stored SSH keys"))
        case .sync:
                            SyncSettingsView()
                                .navigationTitle("Sync")
                                .navigationSubtitle(String(localized: "iCloud sync and data management"))
        case .about:
                            AboutSettingsView()
                                .navigationTitle("About")
                                .navigationSubtitle(String(localized: "Version and links"))
        case .none:
                            ProSettingsView()
                                .navigationTitle("Ghostex Pro")
                                .navigationSubtitle(storeManager.isPro
                                    ? String(localized: "Manage your subscription")
                                    : String(localized: "Upgrade for unlimited features")
                                )
        }
    }

    private var proNavigationRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.orange, Color(red: 0.95, green: 0.5, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 24, height: 24)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Premium")
                .fontWeight(.medium)

            Spacer()

            Text(storeManager.isPro ? String(localized: "PRO") : String(localized: "FREE_PLAN"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(storeManager.isPro ? .white : .primary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(storeManager.isPro
                            ? Color.orange
                            : Color.primary.opacity(0.12)
                        )
                )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func settingsRow(_ title: LocalizedStringKey, icon: String, tag: SettingsSelection) -> some View {
        Label(title, systemImage: icon)
            .tag(tag)
    }
    #endif
}

private struct GhostexCreditsView: View {
    private let vvtermRepositoryURL = URL(string: "https://github.com/vivy-company/vvterm/")!
    private let vvtermAppStoreURL = URL(string: "https://apps.apple.com/app/vvterm/id6757482822")!
    private let vivySponsorURL = URL(string: "https://github.com/sponsors/vivy-company")!

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("VVTerm")
                        .font(.title2.weight(.semibold))

                    Text("Full credit for this app goes to the VVTerm project by vivy-company.")
                        .font(.body)

                    Text("Ghostex Mobile is built from VVTerm. Please support the original work by buying VVTerm Premium or sponsoring vivy-company on GitHub.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Support VVTerm") {
                Link(destination: vvtermRepositoryURL) {
                    Label("Open VVTerm on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Link(destination: vvtermAppStoreURL) {
                    Label("Get VVTerm Premium", systemImage: "sparkles")
                }

                Link(destination: vivySponsorURL) {
                    Label("Sponsor vivy-company", systemImage: "heart.fill")
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
