//  SidebarView.swift
//  Colony
//
//  Created by Yoav Peretz on 17/06/2026.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Binding var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $store.selectedSection) {
                Section {
                    WorkspaceHeader()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 14))
                }

                Section("Workspace") {
                    ForEach(ColonySection.allCases.filter { $0 != .settings }) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
            }

            Divider()

            AccountFooter(profile: $store.profilePreferences) {
                store.selectedSection = .settings
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("")
#if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }
}

private struct WorkspaceHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.linearGradient(
                        colors: [.indigo, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("C")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Colony HQ")
                    .font(.headline)
                Text("Private workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccountFooter: View {
    @Binding var profile: ProfilePreferences
    let openSettings: () -> Void
    @State private var isProfileMenuOpen = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isFilePickerOpen = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                isProfileMenuOpen.toggle()
            } label: {
                ProfileAvatarView(profile: profile, size: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account menu")
            .popover(isPresented: $isProfileMenuOpen, arrowEdge: .bottom) {
                ProfileMenu(profile: $profile, selectedPhotoItem: $selectedPhotoItem, isFilePickerOpen: $isFilePickerOpen)
            }	

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings")
        }
        .fileImporter(isPresented: $isFilePickerOpen, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get(),
                  let data = try? Data(contentsOf: url) else {
                return
            }

            profile.avatarImageData = data
            profile.avatarStyle = .image
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else {
                return
            }

            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    profile.avatarImageData = data
                    profile.avatarStyle = .image
                }
                selectedPhotoItem = nil
            }
        }
    }
}

private struct ProfileMenu: View {
    @Binding var profile: ProfilePreferences
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var isFilePickerOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProfileAvatarView(profile: profile, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.headline)
                    Text(profile.role.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Circle()
                    .fill(.green)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("Online")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Profile")
                    .font(.subheadline.weight(.semibold))

                TextField("Display name", text: $profile.displayName)
                    .textFieldStyle(.roundedBorder)

                Picker("Role", selection: $profile.role) {
                    ForEach(WorkspaceRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                .pickerStyle(.menu)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Profile picture")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        ProfileMenuActionLabel(title: "Photos", systemImage: "photo")
                    }
                    .buttonStyle(.plain)

                    Button {
                        isFilePickerOpen = true
                    } label: {
                        ProfileMenuActionLabel(title: "Files", systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                }

                TextField("Text or emoji", text: $profile.avatarText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: profile.avatarText) {
                        profile.avatarStyle = .text
                        profile.avatarText = String(profile.avatarText.prefix(3))
                    }

                HStack(spacing: 8) {
                    ForEach(ColonyColorToken.allCases) { color in
                        Button {
                            profile.avatarColor = color
                            profile.avatarStyle = .text
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if profile.avatarColor == color && profile.avatarStyle == .text {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Button {
            } label: {
                Label("Switch account", systemImage: "person.2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
            } label: {
                Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
    }
}

private struct ProfileMenuActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ProfileAvatarView: View {
    let profile: ProfilePreferences
    let size: CGFloat

    var body: some View {
        Group {
            if profile.avatarStyle == .image,
               let imageData = profile.avatarImageData,
               let image = platformImage(from: imageData) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(profile.avatarColor.color.gradient)
                    .overlay {
                        Text(profile.avatarText.isEmpty ? "?" : profile.avatarText)
                            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

#if os(macOS)
    private func platformImage(from data: Data) -> NSImage? {
        NSImage(data: data)
    }
#else
    private func platformImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }
#endif
}

#if os(macOS)
private extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#else
private extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#endif
