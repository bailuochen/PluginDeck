import SwiftUI

struct OperationLogView: View {
    @EnvironmentObject private var model: NVMPluginModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.operationTitle)
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.operationStage.isEmpty ? "正在查询可用版本" : model.operationStage)
                        .font(.body.weight(.medium))
                    Spacer()
                    if let progress = model.operationProgress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if model.isOperationRunning || model.operationProgress != nil {
                    ProgressView(value: model.operationProgress, total: 1)
                        .progressViewStyle(.linear)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showsDetails ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 12)
                        Text("详细日志")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsDetails {
                    VStack(spacing: 0) {
                        HStack {
                            Text("NVM 输出")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                model.copyOperationLog()
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("复制任务日志")
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)

                        Divider()

                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(model.operationLog.isEmpty ? "等待输出…" : model.operationLog)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(12)
                                Color.clear.frame(height: 1).id("log-end")
                            }
                            .onChange(of: model.operationLog) { _ in
                                proxy.scrollTo("log-end", anchor: .bottom)
                            }
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            HStack {
                if model.isOperationRunning {
                    Button(role: .destructive) {
                        Task { await model.cancelCurrentOperation() }
                    } label: {
                        Label("取消操作", systemImage: "stop.circle")
                    }
                }
                Spacer()
                Button(model.isOperationRunning ? "后台运行" : "完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .frame(width: 580, height: showsDetails ? 500 : 280)
        .animation(.easeInOut(duration: 0.18), value: showsDetails)
    }

    private var statusText: String {
        switch model.operationStatus {
        case .idle: "等待开始"
        case .running: "操作进行中"
        case .succeeded: "安装成功"
        case .failed: "安装失败"
        case .cancelled: "已取消"
        }
    }

    private var statusIcon: String {
        switch model.operationStatus {
        case .idle: "clock"
        case .running: "arrow.down.circle"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.operationStatus {
        case .idle: .secondary
        case .running: .accentColor
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }
}
