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
    /// The write end of the child's stdin, held for as long as the tunnel
    /// should live. See `start()`.
    private var lifeline: Pipe?

    init(target: RemoteTarget) {
        self.target = target
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// Brings up the forward, replacing any child that has already exited.
    ///
    /// `ExitOnForwardFailure` matters more than it looks: without it ssh
    /// connects happily when the local port is already taken, and the panel
    /// then reads whatever is on the other end of somebody else's tunnel.
    ///
    /// The session runs a remote `cat` on a pipe this process holds, rather
    /// than `-N`, so the tunnel cannot outlive the panel. An `ssh -N` writes
    /// nothing and reads nothing, so a panel that exited without running its
    /// asynchronous `stop()` left it behind: one strix forward survived from
    /// September 24 until it was found on October 3, parented to launchd.
    /// However the panel dies, the kernel closes its end of the pipe, `cat`
    /// sees end of file, and the session and its forward end with it.
    func start() throws {
        stop()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-T"] + SSHOptions.unattended + [
            "-o", "ExitOnForwardFailure=yes",
            "-L", "127.0.0.1:\(target.localPort):\(target.exporterHost):\(target.exporterPort)",
            target.sshDestination,
            "exec cat > /dev/null"
        ]
        let lifeline = Pipe()
        process.standardInput = lifeline
        // ssh's diagnostics are useful to a developer and noise to a panel with
        // nowhere to print them.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        self.process = process
        self.lifeline = lifeline
    }

    func stop() {
        lifeline = nil
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
