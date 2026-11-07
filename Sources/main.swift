import AppKit

let args = CommandLine.arguments
if args.count == 2, args[1] == "--stats" { DebugCommand.stats() }
if args.count == 4, args[1] == "--runner", let r = Runner.all.first(where: { $0.id == args[2] }) { DebugCommand.runner(r) }
if args.count == 2, args[1] == "--bench" { DebugCommand.bench() }
if args.count == 3, args[1] == "--icon" { DebugCommand.icon() }
if args.count == 3, args[1] == "--preview" { DebugCommand.preview() }
if args.count == 3, args[1] == "--render" { DebugCommand.render() }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
