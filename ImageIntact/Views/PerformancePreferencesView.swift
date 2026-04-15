//
//  PerformancePreferencesView.swift
//  ImageIntact
//
//  Performance tab of the Preferences window.
//

import SwiftUI

struct PerformancePreferencesView: View {
    @Bindable var preferences: PreferencesManager = .shared
    @State private var showIntelWarning = false
    @State private var showAppleSiliconWarning = false
    @State private var showStreamCopyInfo = false

    private var systemInfo: SystemCapabilities.SystemInfo? {
        SystemCapabilities.shared.currentSystemInfo
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    systemInfoSection
                    Divider().padding(.vertical, 8)
                    visionFrameworkSection
                    Divider().padding(.vertical, 8)
                    networkPerformanceSection
                    Divider().padding(.vertical, 8)
                    systemBehaviorSection
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 100)
                .padding(.top, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Performance Warning", isPresented: $showIntelWarning) {
            Button("Enable Anyway") {}
            Button("Cancel", role: .cancel) {
                preferences.enableVisionFramework = false
            }
        } message: {
            Text("""
                Vision Framework features are optimized for Apple Silicon and may cause:

                • Significantly slower backup speeds
                • High CPU usage and heat generation
                • Increased memory usage
                • Potential system unresponsiveness

                These features work best on Macs with Apple M-series processors.
                """)
        }
        .alert("Disable Vision Features?", isPresented: $showAppleSiliconWarning) {
            Button("Disable") {}
            Button("Keep Enabled", role: .cancel) {
                preferences.enableVisionFramework = true
            }
        } message: {
            Text("""
                Your Mac's Neural Engine is optimized for these features with minimal performance impact.

                Disabling will turn off future intelligent features like:
                • Photo search and organization
                • Scene detection
                • Content-based grouping
                """)
        }
    }

    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Information")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("Processor:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .trailing)
                        Text(systemInfo?.processorName ?? "Unknown")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 12) {
                        Text("Cores:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .trailing)
                        if let info = systemInfo {
                            if info.performanceCores > 0 {
                                Text("\(info.cpuCores) total (\(info.performanceCores) performance, \(info.efficiencyCores) efficiency)")
                                    .font(.system(size: 13))
                            } else {
                                Text("\(info.cpuCores)")
                                    .font(.system(size: 13))
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text("RAM:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .trailing)
                        if let info = systemInfo {
                            Text(ByteCountFormatter.string(fromByteCount: info.totalRAM, countStyle: .binary))
                                .font(.system(size: 13))
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text("Neural Engine:")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .trailing)
                        if SystemCapabilities.shared.hasNeuralEngine {
                            Label("Available", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.green)
                        } else {
                            Text("Not Available")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(12)
            }
        }
    }

    private var visionFrameworkSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vision Framework")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Text("Future feature for intelligent photo analysis")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable Vision Framework features", isOn: $preferences.enableVisionFramework)
                    .font(.system(size: 13))
                    .disabled(true)
                    .help("Coming in v1.3 - Intelligent photo search and organization")
                    .onChange(of: preferences.enableVisionFramework) { _, newValue in
                        if !SystemCapabilities.shared.isAppleSilicon && newValue {
                            showIntelWarning = true
                        } else if SystemCapabilities.shared.isAppleSilicon && !newValue {
                            showAppleSiliconWarning = true
                        }
                    }

                HStack(spacing: 12) {
                    Text("Processing priority:")
                        .font(.system(size: 13))
                        .frame(width: 130, alignment: .trailing)

                    Picker("", selection: $preferences.visionProcessingPriority) {
                        Text("Low").tag("low")
                        Text("Normal").tag("normal")
                        Text("High").tag("high")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 200)
                    .disabled(true)

                    Spacer()
                }
            }
        }
    }

    private var networkPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Network Performance")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("Use stream-based copy for network volumes", isOn: $preferences.useStreamCopyForNetwork)
                        .font(.system(size: 13))
                        .help("Enable cancellable, throttleable copying for network drives (recommended for SMB)")

                    Button(action: { showStreamCopyInfo = true }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showStreamCopyInfo, arrowEdge: .trailing) {
                        streamCopyInfoPopover
                    }

                    Spacer()
                }

                HStack(spacing: 12) {
                    Text("Network timeout:")
                        .font(.system(size: 13))
                        .frame(width: 140, alignment: .trailing)

                    TextField("", value: $preferences.networkCopyTimeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)

                    Text("seconds")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .help("Abort network copies that stall for this long (default: 90 seconds)")

                HStack(spacing: 12) {
                    Text("Speed limit:")
                        .font(.system(size: 13))
                        .frame(width: 140, alignment: .trailing)

                    TextField("", value: $preferences.networkCopySpeedLimit, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)

                    Text("MB/s (0 = unlimited)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .help("Limit network copy speed to prevent SMB overload")

                HStack(spacing: 12) {
                    Text("Buffer size:")
                        .font(.system(size: 13))
                        .frame(width: 140, alignment: .trailing)

                    Picker("", selection: $preferences.networkBufferSize) {
                        Text("1 MB").tag(1)
                        Text("2 MB").tag(2)
                        Text("4 MB").tag(4)
                        Text("8 MB").tag(8)
                        Text("16 MB").tag(16)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 100)

                    Text("(smaller = more stable)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .help("Smaller buffers can be more stable on flaky connections")

                HStack(spacing: 12) {
                    Text("Retry attempts:")
                        .font(.system(size: 13))
                        .frame(width: 140, alignment: .trailing)

                    Picker("", selection: $preferences.networkRetryAttempts) {
                        Text("No retries").tag(0)
                        Text("1 retry").tag(1)
                        Text("2 retries").tag(2)
                        Text("3 retries").tag(3)
                        Text("5 retries").tag(5)
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 100)

                    Spacer()
                }
                .help("Number of times to retry failed network operations")
            }
        }
    }

    private var streamCopyInfoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stream-Based Copy for Network Volumes")
                .font(.system(size: 13, weight: .semibold))

            Text("When enabled, ImageIntact uses a chunk-based copying method for network drives that provides:")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Label("Cancellable operations", systemImage: "xmark.circle")
                Label("Speed throttling support", systemImage: "speedometer")
                Label("Better timeout handling", systemImage: "clock")
                Label("Progress during large files", systemImage: "chart.line.uptrend.xyaxis")
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)

            Divider()

            Text("When disabled, ImageIntact uses NSFileCoordinator which:")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Label("May be more compatible", systemImage: "checkmark.shield")
                Label("Cannot be cancelled mid-file", systemImage: "exclamationmark.triangle")
                Label("May hang on SMB issues", systemImage: "network.slash")
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)

            Text("Recommended: ON for SMB/NAS drives")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.green)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var systemBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Behavior")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Prevent sleep during backup", isOn: $preferences.preventSleepDuringBackup)
                    .font(.system(size: 13))
                    .help("Keep your Mac awake while backup is running")

                Toggle("Show notification when backup completes", isOn: $preferences.showNotificationOnComplete)
                    .font(.system(size: 13))
                    .help("Display a system notification when backup finishes")
            }
        }
    }
}
