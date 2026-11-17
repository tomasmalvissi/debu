import SwiftUI
import AppKit

/// Visor de la salida de consola de una ejecución iniciada por Debu (RF-15).
struct LogView: View {
    let launch: AppLaunch

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if launch.needsDevCertificate {
                Label {
                    Text("HTTPS necesita el certificado de desarrollo. Ejecutá en la terminal: \(Text("dotnet dev-certs https --trust").font(.body.monospaced()))")
                } icon: {
                    Image(systemName: "lock.trianglebadge.exclamationmark")
                }
                .foregroundStyle(.orange)
                .textSelection(.enabled)
            }

            // ScrollViewReader permite desplazarse por código hasta una línea (para seguir el final del log).
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(launch.lines.enumerated()), id: \.offset) { index, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.callout, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .onChange(of: launch.lines.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo(launch.lines.count - 1, anchor: .bottom)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Logs").font(.headline)
            Text("· \(launch.profile ?? "perfil por defecto") · \(launch.withSecrets ? "con secretos" : "sin secretos")")
                .foregroundStyle(.secondary)
            Spacer()
            status
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(launch.lines.joined(separator: "\n"), forType: .string)
            } label: {
                Label("Copiar", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let code = launch.exitCode {
            Label("Terminó con código \(code)", systemImage: code == 0 ? "checkmark.circle" : "xmark.octagon")
                .foregroundStyle(code == 0 ? Color.secondary : Color.red)
        } else {
            Label("En ejecución", systemImage: "play.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
