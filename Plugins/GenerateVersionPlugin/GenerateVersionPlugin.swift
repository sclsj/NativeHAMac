import PackagePlugin
import Foundation

@main
struct GenerateVersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let outputPath = context.pluginWorkDirectory.appending("GeneratedVersion.swift")
        let scriptPath = context.package.directory.appending("tools").appending("generate_version.sh")
        
        return [
            .prebuildCommand(
                displayName: "Generate Version Information",
                executable: scriptPath,
                arguments: [outputPath.string],
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}
