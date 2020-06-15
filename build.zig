const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("hacky-zig-repl", "src/main.zig");
    exe.addPackagePath("zig-clap", "lib/zig-clap/clap.zig");
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.linkSystemLibrary("readline");

    const run_cmd = exe.run();
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);
}
