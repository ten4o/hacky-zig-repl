# hacky-zig-repl

Just a small wrapper program that provides a repl for the [Zig](https://ziglang.org/) programming language.

#### How to use it?

Clone this git repo with `git clone --recurse-submodules`

Build with the latest zig compiler:
```
cd hacky-zig-repl
zig build
```

Run with: `./zig-cache/bin/hacky-zig-repl`

If needed specify the path to the zig compiler with the `--zig` option.

If you type a simple expression that doesn't end with `;`, then it'll be assigned to a `const` variable and will be printed to the console:
```
>> 2 + 3
_0 = 5
>> "123" ++ "4"
_2 = 1234
>>
```
If you type a line that ends with  `;` then it's considered a full zig statement:
`>>> var s = "1234";`

You can type multi-line statements by opening one of `(`, `[` or `{` and not closing it on the same line. The statement is considered complete when all `(`, `[` and `{` are balanced/closed.
```
>> const S = struct {
>> a: u32,
>> fn doStuff(p: i32) i32 {
>>   return p + 4;
>> }
>> };
>>
```
There's a command that prints the last source listing that compiled successfully: `ls`
```
>> ls
const _0 = 2 + 3;
const _1 = "123" ++ "4";
var s = "1234";
const S = struct {a: u32,fn doStuff(p: i32) i32 {return p + 4;}};
>>
```
There is a builtin convinience function `fn t(v: var) [] const u8 {{ return @typeName(@TypeOf(v)); }}`
