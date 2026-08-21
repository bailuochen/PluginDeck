import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var model: NVMPluginModel
    @State private var pendingRemoval: ProjectRecord?
    @State private var pendingInstallation: ProjectRecord?
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.projects.isEmpty {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    title: isDropTarget ? "松开以添加项目" : "拖入项目目录或手动选择",
                    actionTitle: "选择项目",
                    action: model.addProject
                )
            } else {
                List(model.projects) { project in
                    projectRow(project)
                }
                .listStyle(.inset)
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let directories = urls.filter(\.hasDirectoryPath)
            directories.forEach { model.addProject(path: $0.path) }
            return !directories.isEmpty
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
        .task { await model.refreshAllProjects() }
        .alert(item: $pendingRemoval) { project in
            Alert(
                title: Text("移除 \(project.name)？"),
                message: Text("只会从列表中移除，不会删除项目或版本文件。"),
                primaryButton: .destructive(Text("移除")) {
                    model.removeProject(project)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $pendingInstallation) { project in
            let version = model.projectResolutions[project.id]?.resolvedVersion?.displayName ?? "目标版本"
            return Alert(
                title: Text("安装 \(version)？"),
                message: Text("项目需要的版本尚未安装。安装完成后将自动打开新终端。"),
                primaryButton: .default(Text("安装并打开")) {
                    Task { await model.prepareProject(project, installIfNeeded: true) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("项目")
                    .font(.title2.weight(.semibold))
                Text("\(model.projects.count) 个最近项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.refreshAllProjects() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新扫描")
            .disabled(model.projects.isEmpty || !model.resolvingProjects.isEmpty)

            Button(action: model.addProject) {
                Label("添加项目", systemImage: "plus")
            }
        }
        .padding(18)
    }

    private func projectRow(_ project: ProjectRecord) -> some View {
        let resolution = model.projectResolutions[project.id]
        let isResolving = model.resolvingProjects.contains(project.id)

        return HStack(spacing: 12) {
            Image(systemName: project.directoryExists ? "folder.fill" : "folder.badge.questionmark")
                .font(.system(size: 20))
                .foregroundStyle(project.directoryExists ? Color.accentColor : Color.orange)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.body.weight(.medium))
                Text(isResolving ? "正在解析项目版本…" : (resolution?.summary ?? "等待扫描"))
                    .font(.caption)
                    .foregroundStyle(resolution?.resolvedVersion == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(project.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Menu {
                ForEach(model.state.versions) { version in
                    Button {
                        model.setProjectVersion(version, for: project)
                    } label: {
                        if resolution?.resolvedVersion == version && resolution?.source == .nvmrc {
                            Label(version.displayName, systemImage: "checkmark")
                        } else {
                            Text(version.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "doc.badge.gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("写入 .nvmrc")
            .disabled(!project.directoryExists || model.state.versions.isEmpty)

            Button {
                runProject(project, resolution: resolution)
            } label: {
                if isResolving || model.installingVersion == resolution?.resolvedVersion {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: resolution?.isInstalled == true ? "terminal" : "arrow.down.to.line")
                }
            }
            .buttonStyle(.borderless)
            .frame(width: 26)
            .help(resolution?.isInstalled == true ? "用项目版本打开新终端" : "安装项目版本")
            .disabled(isResolving || resolution?.resolvedVersion == nil || model.installingVersion != nil)

            Menu {
                Button {
                    model.revealProject(project)
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
                Button(role: .destructive) {
                    pendingRemoval = project
                } label: {
                    Label("从列表移除", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("更多操作")
        }
        .frame(minHeight: 66)
        .padding(.vertical, 3)
    }

    private func runProject(_ project: ProjectRecord, resolution: ProjectResolution?) {
        guard let resolution else { return }
        if resolution.isInstalled {
            Task { await model.prepareProject(project, installIfNeeded: false) }
        } else {
            pendingInstallation = project
        }
    }
}
