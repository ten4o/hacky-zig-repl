const clap = @import("zig-clap");
const std = @import("std");
const readline = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h"); // because of free()
    @cInclude("readline/readline.h");
    @cInclude("readline/history.h");
});

const base64 = std.base64;
const crypto = std.crypto;
const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Names = clap.Names;
const Param = clap.Param(clap.Help);

const Scopes = struct {
    braces: i32, // {}
    brakets: i32, // []
    parentheses: i32, // ()
    ends_with_semi: bool,

    fn init() Scopes {
        return Scopes{
            .ends_with_semi = false,
            .braces = 0,
            .brakets = 0,
            .parentheses = 0,
        };
    }

    fn allClosed(self: *Scopes) bool {
        return (self.parentheses == 0 and self.brakets == 0 and self.braces == 0);
    }

    fn notClosed(self: *Scopes) bool {
        return !self.allClosed();
    }

    fn check(s: *Scopes, line: []const u8) void {
        s.ends_with_semi = false;

        if (line.len == 0)
            return;

        const last_ch = line[line.len - 1];
        if (last_ch == ';')
            s.ends_with_semi = true;

        for (line) |ch| {
            switch (ch) {
                '(' => s.parentheses += 1,
                ')' => s.parentheses -= 1,
                '[' => s.brakets += 1,
                ']' => s.brakets -= 1,
                '{' => s.braces += 1,
                '}' => s.braces -= 1,
                else => {},
            }
        }
    }
};
const params = [_]Param{
    clap.parseParam("-h, --help       display this help text and exit                   ") catch unreachable,
    clap.parseParam("-t, --tmp <DIR>  override the folder used to stored temporary files") catch unreachable,
    clap.parseParam("-v, --verbose    print commands before executing them              ") catch unreachable,
    clap.parseParam("    --zig <EXE>  override the path to the Zig executable           ") catch unreachable,
    Param{
        .takes_value = true,
    },
};

fn usage(stream: var) !void {
    try stream.writeAll(
        \\Usage: hacky-zig-repl [OPTION]...
        \\Allows repl like functionality for Zig.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

const repl_template =
    \\usingnamespace @import("std");
    \\fn t(v: var) [] const u8 {{ return @typeName(@TypeOf(v)); }}
    \\pub fn main() !void {{
    \\{}
    \\{}
    \\    if ({})
    \\        try __repl_print_stdout(_{});
    \\}}
    \\
    \\fn __repl_print_stdout(v: var) !void {{
    \\    const stdout = io.getStdOut().outStream();
    \\    try stdout.writeAll("_{} = ");
    \\    try fmt.formatType(
    \\        v,
    \\        "",
    \\        fmt.FormatOptions{{}},
    \\        stdout,
    \\        3,
    \\    );
    \\    try stdout.writeAll("\n");
    \\}}
    \\
;

pub fn main() anyerror!void {
    @setEvalBranchQuota(10000);

    const stdin = io.getStdIn().inStream();
    const stdout = io.getStdOut().outStream();
    const stderr = io.getStdErr().outStream();

    const pa = std.heap.page_allocator;
    var arg_iter = try clap.args.OsIterator.init(pa);
    var args = Clap.parse(pa, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const zig_path = args.option("--zig") orelse "zig";
    const tmp_dir = args.option("--tmp") orelse "/tmp";
    const verbose = args.flag("--verbose");

    var scopes = Scopes.init();
    var last_run_buf = std.ArrayList(u8).init(pa);
    var last_statement = std.ArrayList(u8).init(pa);
    var last_statement_size: usize = 0;
    var i: usize = 0;
    while (true) {
        const last_run = last_run_buf.items;
        var arena = heap.ArenaAllocator.init(pa);
        defer arena.deinit();

        const allocator = &arena.allocator;

        const line_ptr = readline.readline(">> ");
        if (line_ptr == null)
            break;
        defer readline.free(line_ptr);

        const line_len = mem.len(line_ptr);
        const line = mem.trim(u8, line_ptr[0..line_len], " \t");
        if (line.len == 0)
            continue;

        if (mem.eql(u8, line, "ls")) {
            debug.warn("{}", .{last_run_buf.items});
            continue;
        }
        readline.add_history(line_ptr);

        scopes.check(line);

        try last_statement.appendSlice(line);
        last_statement_size += 1;

        if (scopes.notClosed()) {
            continue; // to append lines
        }

        defer {
            last_statement.shrink(0);
            last_statement_size = 0;
        }

        const is_assign_stmt = !(scopes.ends_with_semi or last_statement_size > 1);
        const assignment = if (is_assign_stmt)
            try fmt.allocPrint(allocator, "const _{} = {};", .{ i, line })
        else
            last_statement.items;

        var crypt_src: [224 / 8]u8 = undefined;
        crypto.Blake2s224.hash(last_run, &crypt_src);

        var encoded_src: [base64.Base64Encoder.calcSize(crypt_src.len)]u8 = undefined;
        fs.base64_encoder.encode(&encoded_src, &crypt_src);

        const file_name = try fmt.allocPrint(allocator, "{}/{}.zig", .{ tmp_dir, &encoded_src });
        if (verbose)
            debug.warn("writing source to '{}'\n", .{file_name});

        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();
        try file.outStream().print(repl_template, .{ last_run, assignment, is_assign_stmt, i, i });

        if (verbose)
            debug.warn("running command '{} run {}'\n", .{ zig_path, file_name });
        run(allocator, &[_][]const u8{ zig_path, "run", file_name }) catch |err| {
            debug.warn("error: {}\n", .{err});
            continue;
        };

        try last_run_buf.appendSlice(assignment);
        try last_run_buf.append('\n');
        i += 1;
    }
}

fn run(allocator: *mem.Allocator, argv: []const []const u8) !void {
    const process = try std.ChildProcess.init(argv, allocator);
    defer process.deinit();

    try process.spawn();
    switch (try process.wait()) {
        std.ChildProcess.Term.Exited => |code| {
            if (code != 0)
                return error.ProcessFailed;
        },
        else => return error.ProcessFailed,
    }
}
