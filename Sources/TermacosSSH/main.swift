import Foundation

// ssh invokes SSH_ASKPASS as: <script> "<prompt>". Our askpass.sh shim calls
// this same binary as `Termacos SSH --termacos-askpass <serverID>`, reading
// the server id from TERMACOS_SERVER_ID so we don't have to parse ssh's
// free-text prompt to figure out which Keychain entry to use.
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--termacos-askpass" {
    let account = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : (ProcessInfo.processInfo.environment["TERMACOS_SERVER_ID"] ?? "")
    let prompt = CommandLine.arguments.dropFirst(3).joined(separator: " ")
    if let secret = KeychainService.readAskpassSecret(account: account, prompt: prompt) {
        print(secret)
        exit(0)
    }
    exit(1)
} else {
    TermacosSSHApp.main()
}
