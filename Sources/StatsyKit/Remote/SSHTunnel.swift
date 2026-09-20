import Foundation

/// An `ssh -L` child forwarding a remote exporter to loopback.
///
/// The panel connects through SSH rather than to the exporter directly because
/// ai-1's firewall admits port 9100 from the operations host alone, and that
/// restriction is deliberate. A forward needs no new listener, no firewall
/// change, and no credential inside this app: the key is ssh's business.
final class SSHTunnel {
    private let target: RemoteTarget
    private var process: Process?

    init(target: RemoteTarget) {
        self.target = target
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// Brings up the forward, replacing any child that has already exited.
    ///
    /// `ExitOnForwardFailure` matters more than it looks: without it ssh
    /// connects happily when the local port is already taken, and the panel
    /// then reads whatever is on the other end of somebody else's tunnel.
    func start() throws {
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N", "-T",
            // Fail rather than prompt: there is no terminal to answer on.
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=5",
            // Notice a host that has gone away within ~30s rather than hanging
            // on a dead TCP connection until the kernel gives up.
            "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3",
            "-L", "127.0.0.1:\(target.localPort):\(target.exporterHost):\(target.exporterPort)",
            "\(target.sshUser)@\(target.sshHost)",
        ]
        // ssh's diagnostics are useful to a developer and noise to a panel with
        // nowhere to print them.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        self.process = process
    }

    func stop() {
        guard let process, process.isRunning else {
            self.process = nil
            return
        }
        process.terminate()
        self.process = nil
    }

    deinit {
        process?.terminate()
    }
}
