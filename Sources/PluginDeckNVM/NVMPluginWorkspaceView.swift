import SwiftUI
import PluginDeckCore

public struct NVMPluginWorkspaceView: View {
    @StateObject private var model: NVMPluginModel

    public init(registry: PluginRegistry) {
        _model = StateObject(wrappedValue: NVMPluginModel(registry: registry))
    }

    public var body: some View {
        VStack(spacing: 0) {
            pluginNavigation
            Divider()
            statusBanner
            detail
        }
        .frame(minWidth: 620, minHeight: 520)
        .environmentObject(model)
        .task {
            if model.state.versions.isEmpty {
                await model.refresh()
            }
        }
        .sheet(isPresented: $model.isShowingOperationLog) {
            OperationLogView()
                .environmentObject(model)
        }
    }

    private var pluginNavigation: some View {
        HStack(spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text("NVM")
                        .font(.headline)
                    Text(model.state.defaultVersion?.displayName ?? "未设置默认版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("NVM 功能", selection: $model.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            Spacer()

            if !model.operationTitle.isEmpty {
                Button {
                    model.isShowingOperationLog = true
                } label: {
                    Label("任务日志", systemImage: "text.alignleft")
                }
                .overlay(alignment: .topTrailing) {
                    if model.isOperationRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .offset(x: 6, y: -6)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .installed:
            InstalledVersionsView()
        case .discover:
            DiscoverVersionsView()
        case .projects:
            ProjectsView()
        case .environment:
            EnvironmentView()
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let error = model.errorMessage {
            if model.fallbackCommand != nil {
                NVMStatusBanner(
                    message: error,
                    color: .red,
                    icon: "exclamationmark.circle.fill",
                    actionTitle: "复制命令",
                    action: { model.copyFallbackCommand() },
                    dismiss: { model.dismissError() }
                )
            } else {
                NVMStatusBanner(
                    message: error,
                    color: .red,
                    icon: "exclamationmark.circle.fill",
                    actionTitle: nil,
                    action: nil,
                    dismiss: { model.dismissError() }
                )
            }
        } else if let success = model.successMessage {
            NVMStatusBanner(
                message: success,
                color: .green,
                icon: "checkmark.circle.fill",
                actionTitle: nil,
                action: nil,
                dismiss: { model.successMessage = nil }
            )
        }
    }
}

private struct NVMStatusBanner: View {
    let message: String
    let color: Color
    let icon: String
    let actionTitle: String?
    let action: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("关闭")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(color.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
