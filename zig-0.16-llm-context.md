# Zig 0.16.0 Context Document for LLMs

**Purpose:** This document updates LLM knowledge from Zig 0.13/0.14 to modern Zig (0.15.x/0.16.0). Paste this into any LLM conversation when working with current Zig code.

**Target Version:** Zig 0.16.0 (master) - includes all 0.15.x changes  
**LLM Training Cutoff:** Likely has 0.13/0.14 syntax (January 2025 or earlier)

---

## Critical Breaking Changes Summary

1. **`usingnamespace` REMOVED** - Use explicit declarations or conditionals
2. **I/O completely reworked** - Writers/readers now require explicit buffers
3. **Cast builtins are single-argument** - Use `@as(T, @intCast(val))` not `@intCast(T, val)`
4. **ArrayList is unmanaged by default** - Pass allocator to each operation
5. **Format methods simplified** - No more format strings or options parameters
6. **`async`/`await` keywords removed** - Will return as library functions
7. **Build system requires `root_module`** - Old fields removed

---

## 1. Language Syntax Changes

### 1.1 usingnamespace REMOVED (0.15.x)

**OLD (0.13/0.14):**
```zig
// ❌ NO LONGER WORKS
pub usingnamespace @import("other.zig");
pub usingnamespace if (have_feature) struct {
    pub const foo = 123;
} else struct {};
```

**NEW (0.15+):**
```zig
// ✅ Explicit imports
pub const foo = other.foo;
pub const bar = other.bar;

// ✅ Conditional declarations
pub const foo = if (have_feature) 123 else @compileError("unsupported");

// ✅ Conditional implementation
pub const init = switch (target) {
    .windows => initWindows,
    else => initOther,
};
```

**Rationale:** Better tooling support (autodoc), simpler incremental compilation, encourages good namespacing.

---

### 1.2 Cast Builtins Are Single-Argument (0.15.x)

**OLD (0.13/0.14):**
```zig
// ❌ NO LONGER WORKS - two-argument form removed
const val: u64 = @intCast(u64, input);
const seconds: f64 = @floatFromInt(f64, nanoseconds);
const narrow: i32 = @intCast(i32, wide_value);
const pi: f32 = @floatCast(f32, precise_pi);
```

**NEW (0.15+):**
```zig
// ✅ Single argument + @as for type
const val = @as(u64, @intCast(input));
const seconds = @as(f64, @floatFromInt(nanoseconds));
const narrow = @as(i32, @intCast(wide_value));
const pi: f32 = @floatCast(precise_pi); // or use @as

// The cast builtin returns the SOURCE type, @as coerces to destination
```

**Key Point:** All cast builtins (`@intCast`, `@floatCast`, `@floatFromInt`, `@intFromFloat`) now take ONE argument and return a value that must be coerced to the target type using `@as` or type inference.

---

### 1.3 async/await Keywords Removed (0.15.x)

```zig
// ❌ NO LONGER WORKS
async fn myFunction() !void { ... }
const result = await someCall();
```

**Future:** Will return as **library functions** in `std.Io` interface (not keywords). The `suspend`, `resume` machinery may remain as low-level primitives.

---

### 1.4 Switch on Non-Exhaustive Enums Enhanced (0.15.x)

```zig
// ✅ NEW: Can mix explicit tags with _ prong
switch (enum_val) {
    .special_case_1 => foo(),
    .special_case_2 => bar(),
    _, .special_case_3 => baz(),  // Both unnamed (_) and named
}

// ✅ NEW: Can have both else and _
switch (value) {
    .A => {},
    .C => {},
    else => {}, // Named tags
    _    => {}, // Unnamed tags
}
```

---

### 1.5 Inline Assembly: Typed Clobbers (0.15.x)

**OLD:**
```zig
// ❌ String clobbers
asm volatile ("syscall"
    : [ret] "={rax}" (-> usize)
    : [num] "{rax}" (number)
    : "rcx", "r11"  // Strings
);
```

**NEW:**
```zig
// ✅ Typed clobbers
asm volatile ("syscall"
    : [ret] "={rax}" (-> usize)
    : [num] "{rax}" (number)
    : .{ .rcx = true, .r11 = true }  // Struct literal
);
```

**Auto-fix:** Run `zig fmt` to automatically upgrade this!

---

### 1.6 Arithmetic on undefined Now Errors (0.15.x)

```zig
// ❌ NOW A COMPILE ERROR
const a: u32 = 0;
const b: u32 = undefined;
const c = a + b; // ERROR: use of undefined causes illegal behavior
```

**Rule:** Only operators that can NEVER trigger illegal behavior permit `undefined` as operand. Best practice: never operate on `undefined`.

---

### 1.7 Lossy Int-to-Float Coercion Now Errors (0.15.x)

```zig
// ❌ COMPILE ERROR if precision lost
const val: f32 = 123_456_789; // Too large for f32 precision
```

```zig
// ✅ Use float literal to opt-in to rounding
const val: f32 = 123_456_789.0;
```

---

### 1.8 @ptrCast Can Cast Single-Item Pointer to Slice (0.15.x)

```zig
// ✅ NEW capability
const val: u32 = 1;
const bytes: []const u8 = @ptrCast(&val);
// Returns slice covering same bytes as operand
```

**Note:** Future versions may move this to `@memCast` for safety.

---

## 2. Standard Library I/O Overhaul ("Writergate")

### 2.1 Core Philosophy Change

| Aspect | OLD (0.13/0.14) | NEW (0.15+) |
|--------|-----------------|-------------|
| **Type** | Generic (`anytype`) | Concrete (`std.Io.Reader`/`Writer`) |
| **Buffer** | Separate (`BufferedWriter`) | In interface |
| **Errors** | Pass-through (like `anyerror`) | Precise error sets |
| **Allocator** | Sometimes hidden | Always explicit |

**Key Insight:** The buffer is now **in the interface**, not the implementation. This makes it transparent to optimization while still being non-generic.

---

### 2.2 Writer API Changes

**OLD (0.13/0.14):**
```zig
// ❌ NO LONGER WORKS
const stdout = std.io.getStdOut().writer();
try stdout.print("Hello\n", .{});

var bw = std.io.bufferedWriter(file.writer());
const writer = bw.writer();
try writer.print("data", .{});
try bw.flush();
```

**NEW (0.15+):**
```zig
// ✅ Provide explicit buffer
var stdout_buffer: [4096]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

try stdout.print("Hello\n", .{});
try stdout.flush(); // Don't forget to flush!

// For files
var file_buffer: [4096]u8 = undefined;
var file_writer = file.writer(&file_buffer);
const writer = &file_writer.interface;
try writer.print("data", .{});
try writer.flush();
```

**Pro tip:** Consider making your stdout buffer global in applications.

---

### 2.3 Reader API Changes

**OLD (0.13/0.14):**
```zig
// ❌ NO LONGER WORKS
const file = try std.fs.cwd().openFile("file.txt", .{});
const reader = file.reader();
```

**NEW (0.15+):**
```zig
// ✅ Provide explicit buffer
const file = try std.fs.cwd().openFile("file.txt", .{});
var buffer: [4096]u8 = undefined;
var file_reader = file.reader(&buffer);
const reader = &file_reader.interface;
```

---

### 2.4 New Reader Methods

```zig
// ✅ New convenient APIs
while (reader.takeDelimiterExclusive('\n')) |line| {
    // Process line...
} else |err| switch (err) {
    error.EndOfStream => {},        // Stream ended not on line break
    error.StreamTooLong => {},      // Line didn't fit in buffer
    error.ReadFailed => return err, // Check reader for diagnostics
}
```

**New concepts:**
- **Discarding:** Efficiently skip data without reading it
- **Splatting (writers):** Logical memset without copying (O(M) not O(M*N))
- **Send file:** Direct fd-to-fd copying when OS supports it

---

### 2.5 Adapter for Old Code

```zig
// ✅ Bridge old generic writers to new API
fn foo(old_writer: anytype) !void {
    var adapter = old_writer.adaptToNewApi(&.{});
    const w: *std.Io.Writer = &adapter.new_interface;
    try w.print("{s}", .{"example"});
}
```

---

## 3. Format String Changes

### 3.1 Format Methods Must Use {f} (0.15.x)

**OLD (0.13/0.14):**
```zig
// ❌ Ambiguous - compile error in 0.15+
std.debug.print("{}", .{custom_type});
```

**NEW (0.15+):**
```zig
// ✅ Explicit format method call
std.debug.print("{f}", .{custom_type});

// Or skip format method
std.debug.print("{any}", .{custom_type});
```

**Use `-freference-trace` flag to find all format string breakage.**

---

### 3.2 Format Method Signature Changed (0.15.x)

**OLD (0.13/0.14):**
```zig
// ❌ NO LONGER WORKS
pub fn format(
    self: @This(),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    // ...
}
```

**NEW (0.15+):**
```zig
// ✅ Simplified signature
pub fn format(
    self: @This(),
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.print("value: {d}", .{self.value});
}
```

**FormatOptions removed** - now only for numbers. For custom state, use:
1. **Different format methods** - `formatB`, `formatHex`, etc.
2. **`std.fmt.Alt`** - Wrapper with context
3. **Return a struct** - With its own format method

---

### 3.3 New Format Specifiers (0.15.x)

```zig
// ✅ New specifiers
try writer.print("{t}", .{my_enum});       // @tagName() shorthand
try writer.print("{t}", .{my_error});      // @errorName() shorthand
try writer.print("{b64}", .{data});        // Base64 encoding
try writer.print("{d}", .{custom_number}); // Calls formatNumber method
```

---

### 3.4 Unicode Alignment Removed (0.15.x)

**OLD:** Format string alignment considered Unicode codepoints (partially).  
**NEW:** Alignment is ASCII/bytes only. For Unicode, use a full Unicode library.

---

## 4. ArrayList Changes

### 4.1 Unmanaged is Default (0.15.x)

**OLD (0.13/0.14):**
```zig
// ❌ This is now the MANAGED version
var list = std.ArrayList(u8).init(allocator);
try list.append(item);
list.deinit();
```

**NEW (0.15+):**
```zig
// ✅ Default is unmanaged - pass allocator to each operation
var list = std.ArrayList(u8){};
try list.append(allocator, item);
try list.appendSlice(allocator, items);
list.deinit(allocator);

// ✅ If you really want allocator field (now explicit)
var list = std.array_list.Managed(u8).init(allocator);
try list.append(item);
list.deinit();
```

**Migration:** 
- `std.ArrayList` → Keep same, add allocator params
- `std.ArrayListAligned` → `std.array_list.AlignedManaged` (or unmanaged + params)
- `std.ArrayListUnmanaged` → Now just `std.ArrayList`

**Rationale:** Simpler default (no extra field), better for nested containers, static initialization, clearer allocator usage.

---

### 4.2 New "Bounded" Methods (0.15.x)

```zig
// ✅ Stack-buffer-backed ArrayList
var buffer: [8]i32 = undefined;
var list = std.ArrayListUnmanaged(i32).initBuffer(&buffer);
try list.appendSliceBounded(items); // Asserts if exceeds capacity

// All "AssumeCapacity" methods now have "Bounded" variants
```

---

## 5. Data Structure Changes

### 5.1 BoundedArray REMOVED (0.15.x)

**OLD (0.13/0.14):**
```zig
// ❌ NO LONGER EXISTS
var stack = try std.BoundedArray(i32, 8).fromSlice(items);
```

**NEW (0.15+):**
```zig
// ✅ Use ArrayList with stack buffer
var buffer: [8]i32 = undefined;
var stack = std.ArrayListUnmanaged(i32).initBuffer(&buffer);
try stack.appendSliceBounded(items);
```

**Rationale:** BoundedArray encouraged arbitrary limits and had hidden costs (copying undefined memory). ArrayList works for stack buffers too.

---

### 5.2 LinkedList De-Genericified (0.15.x)

**OLD (0.13/0.14):**
```zig
// ❌ Generic version removed
var list = std.DoublyLinkedList(MyType).init();
```

**NEW (0.15+):**
```zig
// ✅ Intrusive list with @fieldParentPtr
const MyType = struct {
    node: std.DoublyLinkedList.Node = .{},
    data: i32,
    
    // ... use @fieldParentPtr("node", node_ptr) to get back to MyType
};

var list: std.DoublyLinkedList = .{};
```

**Benefit:** Less code bloat, encourages intrusive design (better performance).

---

### 5.3 Ring Buffers Consolidated (0.15.x)

**REMOVED:**
- `std.fifo.LinearFifo` (poorly designed)
- `std.RingBuffer` (redundant)
- Various internal ring buffers

**REPLACEMENT:** Most use cases now served by `std.Io.Reader`/`Writer` (which are ring buffers).

**When you need a custom ring buffer:** Consider if `std.Io.Reader`/`Writer` would work first.

---

## 6. Compression API Changes (0.15.x)

### 6.1 flate/zlib/gzip Reworked

**OLD (0.13/0.14):**
```zig
// ❌ NO LONGER WORKS
var decompress = try std.compress.zlib.decompressor(reader);
```

**NEW (0.15+):**
```zig
// ✅ Unified flate API with container parameter
var decompress_buffer: [std.compress.flate.max_window_len]u8 = undefined;
var decompress: std.compress.flate.Decompress = .init(reader, .zlib, &decompress_buffer);
const decompress_reader: *std.Io.Reader = &decompress.reader;

// If piping directly to writer, use empty buffer
var decompress: std.compress.flate.Decompress = .init(reader, .zlib, &.{});
const n = try decompress.streamRemaining(writer);
```

**Container options:** `.zlib`, `.gzip`, `.raw`

**Note:** Compression (deflate) was REMOVED. Copy old code or use third-party package.

---

## 7. Build System Changes

### 7.1 root_module Required (0.15.x)

**OLD (0.13/0.14):**
```zig
// ❌ NO LONGER WORKS - deprecated fields removed
const exe = b.addExecutable(.{
    .name = "myapp",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});
```

**NEW (0.15+):**
```zig
// ✅ Use root_module field
const exe = b.addExecutable(.{
    .name = "myapp",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }),
});
```

**Or use the shorthand for simple cases:**
```zig
const exe = b.addExecutable(.{
    .name = "myapp",
    .root_module = .{
        .root_source_file = b.path("src/main.zig"),
    },
});
```

---

### 7.2 zig init Changes (0.15.x)

**NEW template includes:**
- Both module and executable boilerplate
- Shows how to split logic between reusable module and application

**NEW flag:**
```bash
zig init --minimal  # or -m
# Generates minimal build.zig stub + build.zig.zon
```

---

### 7.3 zig build --watch on macOS Fixed (0.15.x)

Now uses File System Events API - fast and reliable. Safe to use with all editors.

---

### 7.4 Web Interface and Time Reports (0.15.x)

```bash
zig build --webui              # Start web interface
zig build --webui --time-report # Include timing info
```

Shows which files/declarations are slow to compile. Great for optimization.

---

## 8. Standard Library Deletions/Deprecations

### 8.1 Deleted (0.15.x)

```zig
// ❌ ALL REMOVED
std.io.BufferedReader     // → Use std.Io.Reader with buffer
std.io.BufferedWriter     // → Provide buffer to writer()
std.io.CountingWriter     // → Use .Discarding, .Allocating, or .fixed
std.io.SeekableStream     // → Use concrete types (File.Reader, ArrayListUnmanaged)
std.io.BitReader          // → Couple with your stream implementation
std.io.BitWriter          // → Couple with your stream implementation
std.io.LimitedReader      // → Removed
std.fifo.LinearFifo       // → Use std.Io.Reader/Writer
std.RingBuffer            // → Use std.Io.Reader/Writer
std.BoundedArray          // → Use ArrayList + stack buffer
```

---

### 8.2 Renamed/Deprecated (0.15.x)

```zig
// Old → New
std.fs.File.reader()                 → std.fs.File.deprecatedReader()
std.fs.File.writer()                 → std.fs.File.deprecatedWriter()
std.fmt.fmtSliceEscapeLower          → std.ascii.hexEscape
std.fmt.fmtSliceEscapeUpper          → std.ascii.hexEscape
std.zig.fmtEscapes                   → std.zig.fmtString
std.fmt.fmtSliceHexLower             → use {x} specifier
std.fmt.fmtSliceHexUpper             → use {X} specifier
std.fmt.fmtIntSizeDec                → use {B} specifier
std.fmt.fmtIntSizeBin                → use {Bi} specifier
std.fmt.fmtDuration                  → use {D} specifier
std.fmt.Formatter                    → std.fmt.Alt (API changed)
std.fmt.format                       → std.Io.Writer.print
std.io.GenericReader                 → std.Io.Reader
std.io.GenericWriter                 → std.Io.Writer
std.io.AnyReader                     → std.Io.Reader
std.io.AnyWriter                     → std.Io.Writer
```

---

### 8.3 File Operations (0.15.x)

```zig
// Removed
fs.Dir.copyFile()        // Can no longer fail with OutOfMemory
fs.File.WriteFileOptions // Removed
fs.File.writeFileAll     // Removed - use File.Writer
posix.sendfile           // → fs.File.Reader.sendFile
```

---

## 9. HTTP Client/Server Changes (0.15.x)

### 9.1 Complete Rework

**Key changes:**
- No longer depends on `std.net` - only uses `std.Io.Reader`/`Writer`
- All arbitrary limits removed (e.g., header count)
- Shared `std.http.Reader` and `std.http.BodyWriter`

**OLD Client:**
```zig
// ❌ NO LONGER WORKS
var server_header_buffer: [1024]u8 = undefined;
var req = try client.open(.GET, uri, .{
    .server_header_buffer = &server_header_buffer,
});
defer req.deinit();
try req.send();
try req.wait();
const body_reader = try req.reader();
```

**NEW Client:**
```zig
// ✅ New API
var req = try client.request(.GET, uri, .{});
defer req.deinit();

try req.sendBodiless();
var response = try req.receiveHead(&.{});

// Iterate headers BEFORE calling reader() (strings invalidated after)
var it = response.head.iterateHeaders();
while (it.next()) |header| {
    // Use header.name, header.value
}

var reader_buffer: [4096]u8 = undefined;
const body_reader = response.reader(&reader_buffer);
```

**OLD Server:**
```zig
// ❌ NO LONGER WORKS
var read_buffer: [8000]u8 = undefined;
var server = std.http.Server.init(connection, &read_buffer);
```

**NEW Server:**
```zig
// ✅ Separate buffers for recv/send
var recv_buffer: [4000]u8 = undefined;
var send_buffer: [4000]u8 = undefined;
var conn_reader = connection.stream.reader(&recv_buffer);
var conn_writer = connection.stream.writer(&send_buffer);
var server = std.http.Server.init(conn_reader.interface(), &conn_writer.interface);
```

---

### 9.2 TLS Client (0.15.x)

**Now only depends on `std.Io.Reader`/`Writer`** - no `std.net` or `std.fs` dependencies.

---

## 10. Compiler Backend Progress

### 10.1 x86 Backend DEFAULT in Debug (0.15.x)

**Key facts:**
- ~5x faster compilation than LLVM in Debug
- Enabled by default for x86_64 in Debug mode (except NetBSD, OpenBSD, Windows)
- Passes MORE behavior tests than LLVM (1984/2008 vs 1977/2008)
- Supports incremental compilation (WIP)
- Emits slower code than LLVM (but faster compile time matters more in Debug)

**Override if needed:**
```bash
zig build-exe -fllvm  # Force LLVM backend
```

Or in build.zig:
```zig
exe.use_llvm = true;
```

---

### 10.2 aarch64 Backend (WIP in 0.15.x)

- Passing 1656/1972 (84%) behavior tests
- New design, expected to be faster than x86 backend
- Not ready for use yet, but progressing rapidly
- Goal: Default for Debug mode in future release

---

### 10.3 Incremental Compilation (Experimental)

**Status:** Experimental, has known bugs, can cause miscompilations.

**Safe usage:**
```bash
zig build --watch -fincremental -fno-emit-bin
# Use for compile errors only, not binaries yet
```

**Build system:**
```bash
zig build --watch -fincremental -Dno-bin
```

**Very fast rebuilds** - only recompiles changed code. Worth trying for large projects.

---

## 11. Toolchain Updates (0.15.x)

- **LLVM 20.1.8** (includes Clang, libc++, etc.)
- **glibc 2.42** available for cross-compilation
- **FreeBSD/NetBSD** - Cross-compile with dynamic libc now supported
- **MinGW-w64** updated
- **zig libc** - Started reimplementing common functions in Zig (sharing code between musl/wasi/mingw)

---

## 12. Quick Migration Checklist

### Must-fix items (will not compile):

- [ ] Remove all `usingnamespace` usage
- [ ] Update cast builtins to single-argument form (`@as(T, @intCast(x))`)
- [ ] Fix build.zig to use `root_module`
- [ ] Update I/O code to provide explicit buffers
- [ ] Change `{}` to `{f}` for custom format methods
- [ ] Update format() method signatures (remove fmt string and options)
- [ ] Replace BoundedArray with ArrayList + buffer
- [ ] Update ArrayList usage (pass allocator to operations)
- [ ] Update compression API (flate/zlib/gzip)

### Run auto-fix:

```bash
zig fmt  # Fixes inline assembly clobbers automatically
```

### Consider:

- [ ] Use `-freference-trace` to find format string issues
- [ ] Try `--watch -fincremental -fno-emit-bin` for fast rebuilds
- [ ] Make stdout buffers global for better performance
- [ ] Consider using x86 backend (default) for faster Debug builds

---

## 13. For Freestanding/Kernel Development

### ✅ Works in freestanding:

```zig
std.mem.*           // Memory operations (@memcpy, @memset, etc.)
std.fmt.*           // Formatting (with your custom writer)
std.debug.*         // Assertions (if you implement panic)
std.math.*          // Math functions
std.ArrayList       // Works great with custom allocator
std.HashMap         // Works great with custom allocator
```

### ❌ Doesn't work (requires OS):

```zig
std.fs.*    // You're building the filesystem
std.net.*   // You're building the network stack
std.os.*    // You ARE the OS
std.io.*    // Need to provide your own Reader/Writer backends
```

### ✅ Perfect for kernels:

The new I/O API is **excellent** for kernel development:
- Explicit buffers (no hidden allocations)
- Concrete types (no generic bloat)
- Precise error sets
- Works with custom device drivers

```zig
// Example: VGA text mode writer
var vga_buffer: [80]u8 = undefined;
var vga_writer = vgaDevice.writer(&vga_buffer);
const vga = &vga_writer.interface;
try vga.print("Kernel booted!\n", .{});
try vga.flush();
```

---

## 14. Common Patterns and Idioms

### Pattern: Zero-bit mixins (replaces usingnamespace)

**OLD:**
```zig
pub usingnamespace CounterMixin(Foo);
```

**NEW:**
```zig
const Foo = struct {
    count: u32 = 0,
    counter: CounterMixin(Foo) = .{},
};

// Use: foo.counter.increment()
// Inside mixin: const parent: *T = @fieldParentPtr("counter", m);
```

---

### Pattern: Feature detection

**OLD:**
```zig
if (@hasDecl(std.os, "feature")) { ... }
```

**NEW:**
```zig
// Use void as sentinel
pub const feature = if (have_feature) actual_impl else {};

// Check with:
if (@TypeOf(thing.feature) != void) {
    // Feature is supported
}
```

---

### Pattern: Conditional compilation

```zig
// Simple
pub const init = if (condition) initA else initB;

// With safety
pub const foo = if (have_foo)
    123
else
    @compileError("foo not supported on this target");
```

---

## 15. Debugging Tips

### Finding format string issues:

```bash
zig build -freference-trace  # Shows where types come from
```

### Finding usingnamespace:

```bash
grep -r "usingnamespace" src/
```

### Testing with LLVM backend:

```bash
zig build -fllvm  # If self-hosted backend has issues
```

### Watch mode for fast iteration:

```bash
zig build --watch  # Now works on macOS!
zig build --watch -fincremental -fno-emit-bin  # Even faster
```

---

## 16. Future Direction (0.16.0 and Beyond)

### Main themes for 0.16.0:

1. **Async I/O** - I/O as an interface (like Allocator)
2. **aarch64 backend** - Default for Debug mode
3. **Linker improvements** - Eliminate LLD dependency, better incremental
4. **Fuzzer** - Competitive with AFL

### I/O as an Interface

All I/O will require an `std.Io` instance (like `Allocator`):
- File system operations
- Networking
- Timers
- Synchronization

**Benefits:**
- Optimal, reusable code agnostic to concurrency model
- Express asynchrony without async/await keywords
- Catch more bugs
- Event loops as first-class citizens

---

## 17. Key Takeaways for LLMs

When generating Zig code for 0.15.x/0.16.0:

1. **Never use `usingnamespace`** - Use conditionals or explicit declarations
2. **Always provide buffers to readers/writers** - No more `getStdOut().writer()`
3. **Casts are single-argument** - Use `@as(T, @intCast(x))`
4. **ArrayList needs allocator on each call** - `list.append(allocator, item)`
5. **Format methods are simpler** - Just `fn format(self, writer) Error!void`
6. **Use `{f}` for format methods** - Not `{}`
7. **Always flush writers** - No buffering by default
8. **Build system needs root_module** - Not `root_source_file` directly
9. **Prefer explicit over implicit** - Zig philosophy
10. **Check compiler errors** - They're usually clear and helpful

---

## 18. Resources

- **Official docs:** https://ziglang.org/documentation/0.15.1/
- **Std lib source:** `lib/std/` in Zig installation (best examples!)
- **Release notes:** https://ziglang.org/download/0.15.1/release-notes.html
- **This document version:** 2025-01-20 (for Zig 0.16.0 master)

---

## Version History

- **v1.0** (2025-01-20): Initial version covering 0.13/0.14 → 0.15.x/0.16.0 migration

---

**End of context document. Paste this at the start of conversations about modern Zig code.**
