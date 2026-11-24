import Foundation

/// `swiftport sync` bridge codegen for Android (Kotlin + JNI C shim) and
/// Windows (C# P/Invoke). Output lands in `Bridges/` — generated,
/// gitignored, regenerated on every sync.
///
/// Both bridges speak JSON over the `swiftport_*` C ABI exported by the
/// `AppCoreCABI` dynamic library built from `Core/`. The Kotlin/C# models
/// mirror the `Codable` wire format exactly; `swiftport verify` contract
/// fixtures remain the source of truth for states.
public enum BridgeGen {

    /// Writes Kotlin bindings, the JNI C shim and CMakeLists under
    /// `Bridges/AndroidJNI/`. Returns the paths written (relative to root).
    @discardableResult
    public static func generateAndroid(root: URL, config: ProjectConfig) throws -> [String] {
        let bundleID = Template.Tokens(
            appName: config.name, bundleIDPrefix: config.bundleIDPrefix
        ).bundleID
        let pkg = "\(bundleID).bridge"
        let pkgPath = pkg.replacingOccurrences(of: ".", with: "/")
        let jniPrefix = "Java_" + pkg.replacingOccurrences(of: ".", with: "_")
            + "_SwiftPortBridge"

        let files: [(String, String)] = [
            ("Bridges/AndroidJNI/src/main/java/\(pkgPath)/SwiftPortBridge.kt",
             kotlinBridge(packageName: pkg, jniPrefix: jniPrefix)),
            ("Bridges/AndroidJNI/src/main/cpp/jni_shim.c",
             jniShim(jniPrefix: jniPrefix)),
            ("Bridges/AndroidJNI/CMakeLists.txt", androidCMake),
            ("Bridges/AndroidJNI/README.md", androidReadme(bundleID: bundleID)),
        ]
        return try write(files, root: root)
    }

    /// Writes the C# P/Invoke wrapper under `Bridges/WindowsABI/`.
    /// Returns the paths written (relative to root).
    @discardableResult
    public static func generateWindows(root: URL, config: ProjectConfig) throws -> [String] {
        let bundleID = Template.Tokens(
            appName: config.name, bundleIDPrefix: config.bundleIDPrefix
        ).bundleID
        let files: [(String, String)] = [
            ("Bridges/WindowsABI/SwiftPortBridge.cs",
             csharpBridge(namespaceName: "\(bundleID).Bridge")),
            ("Bridges/WindowsABI/README.md", windowsReadme(bundleID: bundleID)),
        ]
        return try write(files, root: root)
    }

    // MARK: - File writing

    private static func write(_ files: [(String, String)], root: URL) throws -> [String] {
        let fm = FileManager.default
        var written: [String] = []
        for (relative, contents) in files {
            let url = root.appendingPathComponent(relative)
            try fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            written.append(relative)
        }
        return written
    }

    // MARK: - Kotlin

    private static func kotlinBridge(packageName: String, jniPrefix: String) -> String {
        """
        package \(packageName)

        import org.json.JSONObject

        /// Bridge to the Swift `AppCoreCABI` dynamic library.
        ///
        /// `libswiftportcore.so` is produced by `swift build` in Core/ for
        /// each Android ABI (Swift Android SDK); `libswiftport_jni.so` is
        /// built from `Bridges/AndroidJNI` by the NDK/CMake integration in
        /// `Apps/Android/app/build.gradle.kts`. The JNI shim resolves the
        /// Swift symbols with dlopen, so no link-time dependency is needed.
        ///
        /// Wire format: every call returns the JSON encoding of
        /// `TaskListSnapshot` (or null on failure). Models below mirror the
        /// Swift `Codable` schema — keep field names identical.
        object SwiftPortBridge {
            init {
                System.loadLibrary("swiftport_jni")
            }

            enum class TaskPhase { LOADING, EMPTY, LOADED, ERROR }

            data class TaskItem(
                val id: String,
                val title: String,
                val notes: String,
                val isCompleted: Boolean,
                val priority: String,
                val createdAt: String,
            )

            data class TaskListSnapshot(
                val phase: TaskPhase,
                val tasks: List<TaskItem>,
                val errorMessage: String?,
            )

            private external fun nativeAbiVersion(): Int
            private external fun nativeFixtureSnapshotJson(fixtureJson: String): String?
            private external fun nativeStoreSnapshotJson(): String?
            private external fun nativeStoreAddTask(title: String, notes: String, priority: String): String?
            private external fun nativeStoreToggleTask(id: String): String?
            private external fun nativeStoreDeleteTask(id: String): String?
            private external fun nativeStoreReset(): String?

            fun abiVersion(): Int = nativeAbiVersion()

            /// Deterministic snapshot for a Verification/Contracts fixture —
            /// the same JSON every platform's contract tests consume.
            fun snapshotFromFixture(fixtureJson: String): TaskListSnapshot? =
                nativeFixtureSnapshotJson(fixtureJson)?.let(::parseSnapshot)

            fun storeSnapshot(): TaskListSnapshot? =
                nativeStoreSnapshotJson()?.let(::parseSnapshot)

            fun addTask(title: String, notes: String = "", priority: String = "medium"): TaskListSnapshot? =
                nativeStoreAddTask(title, notes, priority)?.let(::parseSnapshot)

            fun toggleTask(id: String): TaskListSnapshot? =
                nativeStoreToggleTask(id)?.let(::parseSnapshot)

            fun deleteTask(id: String): TaskListSnapshot? =
                nativeStoreDeleteTask(id)?.let(::parseSnapshot)

            fun resetStore(): TaskListSnapshot? =
                nativeStoreReset()?.let(::parseSnapshot)

            private fun parseSnapshot(json: String): TaskListSnapshot {
                val o = JSONObject(json)
                val phase = when (o.getString("phase")) {
                    "loading" -> TaskPhase.LOADING
                    "empty" -> TaskPhase.EMPTY
                    "loaded" -> TaskPhase.LOADED
                    else -> TaskPhase.ERROR
                }
                val tasks = o.optJSONArray("tasks")?.let { array ->
                    (0 until array.length()).map { i ->
                        val t = array.getJSONObject(i)
                        TaskItem(
                            id = t.getString("id"),
                            title = t.getString("title"),
                            notes = t.optString("notes"),
                            isCompleted = t.optBoolean("isCompleted"),
                            priority = t.optString("priority"),
                            createdAt = t.optString("createdAt"),
                        )
                    }
                } ?: emptyList()
                val errorMessage = if (o.isNull("errorMessage")) null else o.optString("errorMessage")
                return TaskListSnapshot(phase, tasks, errorMessage)
            }
        }
        """
    }

    // MARK: - JNI C shim

    /// JNI shim forwarding to `swiftport_*` C ABI symbols. Resolves the
    /// Swift library lazily via dlopen("libswiftportcore.so") so this shim
    /// compiles without the Swift Android SDK installed.
    private static func jniShim(jniPrefix: String) -> String {
        """
        // Generated by `swiftport sync` — do not edit.
        // Forwards JNI calls to the Swift AppCoreCABI library
        // (libswiftportcore.so), resolved lazily via dlopen.
        #include <jni.h>
        #include <dlfcn.h>
        #include <stdlib.h>
        #include <stdint.h>

        static void *swiftport_sym(const char *name) {
            static void *handle = NULL;
            if (!handle) {
                handle = dlopen("libswiftportcore.so", RTLD_NOW | RTLD_LOCAL);
            }
            return handle ? dlsym(handle, name) : NULL;
        }

        static void free_swift(const char *ptr) {
            typedef void (*free_fn)(const char *);
            free_fn fn = (free_fn)swiftport_sym("swiftport_free_string");
            if (fn && ptr) fn(ptr);
        }

        // UTF-16 (jchar) -> UTF-8 for the Swift side.
        static char *jstring_to_utf8(JNIEnv *env, jstring s) {
            jsize len = (*env)->GetStringLength(env, s);
            const jchar *chars = (*env)->GetStringChars(env, s, NULL);
            if (!chars) return NULL;
            char *out = (char *)malloc((size_t)len * 3 + 1);
            if (!out) {
                (*env)->ReleaseStringChars(env, s, chars);
                return NULL;
            }
            char *w = out;
            for (jsize i = 0; i < len; i++) {
                uint32_t cp = chars[i];
                if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < len) {
                    uint32_t lo = chars[i + 1];
                    if (lo >= 0xDC00 && lo <= 0xDFFF) {
                        cp = 0x10000u + ((cp - 0xD800u) << 10) + (lo - 0xDC00u);
                        i++;
                    }
                }
                if (cp < 0x80) {
                    *w++ = (char)cp;
                } else if (cp < 0x800) {
                    *w++ = (char)(0xC0 | (cp >> 6));
                    *w++ = (char)(0x80 | (cp & 0x3F));
                } else if (cp < 0x10000) {
                    *w++ = (char)(0xE0 | (cp >> 12));
                    *w++ = (char)(0x80 | ((cp >> 6) & 0x3F));
                    *w++ = (char)(0x80 | (cp & 0x3F));
                } else {
                    *w++ = (char)(0xF0 | (cp >> 18));
                    *w++ = (char)(0x80 | ((cp >> 12) & 0x3F));
                    *w++ = (char)(0x80 | ((cp >> 6) & 0x3F));
                    *w++ = (char)(0x80 | (cp & 0x3F));
                }
            }
            *w = '\\0';
            (*env)->ReleaseStringChars(env, s, chars);
            return out;
        }

        // UTF-8 -> jstring via NewString (UTF-16). NewStringUTF expects
        // modified UTF-8, which plain UTF-8 is not for non-BMP characters.
        static int utf8_decode(const unsigned char **pp, uint32_t *out) {
            const unsigned char *p = *pp;
            uint32_t cp;
            int n;
            if (*p < 0x80) { cp = *p; n = 1; }
            else if ((*p & 0xE0) == 0xC0) { cp = *p & 0x1F; n = 2; }
            else if ((*p & 0xF0) == 0xE0) { cp = *p & 0x0F; n = 3; }
            else { cp = *p & 0x07; n = 4; }
            for (int i = 1; i < n; i++) cp = (cp << 6) | (p[i] & 0x3F);
            *pp = p + n;
            *out = cp;
            return n;
        }

        static jstring utf8_to_jstring(JNIEnv *env, const char *utf8) {
            const unsigned char *p = (const unsigned char *)utf8;
            const unsigned char *q = p;
            uint32_t cp;
            size_t units = 0;
            while (*q) {
                utf8_decode(&q, &cp);
                units += cp > 0xFFFF ? 2 : 1;
            }
            jchar *buf = (jchar *)malloc((units + 1) * sizeof(jchar));
            if (!buf) return NULL;
            size_t j = 0;
            while (*p) {
                utf8_decode(&p, &cp);
                if (cp > 0xFFFF) {
                    cp -= 0x10000u;
                    buf[j++] = (jchar)(0xD800u + (cp >> 10));
                    buf[j++] = (jchar)(0xDC00u + (cp & 0x3FFu));
                } else {
                    buf[j++] = (jchar)cp;
                }
            }
            jstring s = (*env)->NewString(env, buf, (jsize)j);
            free(buf);
            return s;
        }

        // Calls a swiftport_* function returning char*; converts the JSON
        // result to a jstring and releases the Swift-side allocation.
        typedef const char *(*json_fn)(const char *);
        typedef const char *(*json_fn0)(void);

        static jstring call_json0(JNIEnv *env, json_fn0 fn) {
            if (!fn) return NULL;
            const char *out = fn();
            if (!out) return NULL;
            jstring s = utf8_to_jstring(env, out);
            free_swift(out);
            return s;
        }

        JNIEXPORT jint JNICALL
        \(jniPrefix)_nativeAbiVersion(JNIEnv *env, jobject thiz) {
            (void)env; (void)thiz;
            typedef jint (*fn)(void);
            fn f = (fn)swiftport_sym("swiftport_abi_version");
            return f ? f() : -1;
        }

        JNIEXPORT jstring JNICALL
        \(jniPrefix)_nativeFixtureSnapshotJson(JNIEnv *env, jobject thiz, jstring fixtureJson) {
            (void)thiz;
            json_fn fn = (json_fn)swiftport_sym("swiftport_fixture_snapshot_json");
            char *arg = jstring_to_utf8(env, fixtureJson);
            const char *out = fn && arg ? fn(arg) : NULL;
            free(arg);
            if (!out) return NULL;
            jstring s = utf8_to_jstring(env, out);
            free_swift(out);
            return s;
        }

        JNIEXPORT jstring JNICALL
        \(jniPrefix)_nativeStoreSnapshotJson(JNIEnv *env, jobject thiz) {
            (void)thiz;
            return call_json0(env, (json_fn0)swiftport_sym("swiftport_store_snapshot_json"));
        }

        JNIEXPORT jstring JNICALL
        \(jniPrefix)_nativeStoreAddTask(JNIEnv *env, jobject thiz,
                                        jstring title, jstring notes, jstring priority) {
            (void)thiz;
            typedef const char *(*json_fn3)(const char *, const char *, const char *);
            json_fn3 fn = (json_fn3)swiftport_sym("swiftport_store_add_task");
            if (!fn) return NULL;
            char *t = jstring_to_utf8(env, title);
            char *n = jstring_to_utf8(env, notes);
            char *p = jstring_to_utf8(env, priority);
            const char *out = fn(t, n, p);
            free(t); free(n); free(p);
            if (!out) return NULL;
            jstring s = utf8_to_jstring(env, out);
            free_swift(out);
            return s;
        }

        JNIEXPORT jstring JNICALL
        \(jniPrefix)_nativeStoreToggleTask(JNIEnv *env, jobject thiz, jstring id) {
            (void)thiz;
            json_fn fn = (json_fn)swiftport_sym("swiftport_store_toggle_task");
            char *arg = jstring_to_utf8(env, id);
            const char *out = fn && arg ? fn(arg) : NULL;
            free(arg);
            if (!out) return NULL;
            jstring s = utf8_to_jstring(env, out);
            free_swift(out);
            return s;
        }

        JNIEXPORT jstring JNICALL
        \(jniPrefix)_nativeStoreDeleteTask(JNIEnv *env, jobject thiz, jstring id) {
            (void)thiz;
            json_fn fn = (json_fn)swiftport_sym("swiftport_store_delete_task");
            char *arg = jstring_to_utf8(env, id);
            const char *out = fn && arg ? fn(arg) : NULL;
            free(arg);
            if (!out) return NULL;
            jstring s = utf8_to_jstring(env, out);
            free_swift(out);
            return s;
        }

        JNIEXPORT jstring JNICALL
        \(jniPrefix)_nativeStoreReset(JNIEnv *env, jobject thiz) {
            (void)thiz;
            return call_json0(env, (json_fn0)swiftport_sym("swiftport_store_reset"));
        }
        """
    }

    private static let androidCMake = """
        # Generated by `swiftport sync` — builds libswiftport_jni.so from the
        # JNI shim. The Swift core (libswiftportcore.so) is resolved at
        # runtime via dlopen; drop prebuilt per-ABI .so files into
        # app/src/main/jniLibs/<abi>/ (see README.md).
        cmake_minimum_required(VERSION 3.22.1)
        project(swiftport_jni C)

        add_library(swiftport_jni SHARED src/main/cpp/jni_shim.c)

        find_library(dl-lib dl)
        target_link_libraries(swiftport_jni ${dl-lib})
        """

    private static func androidReadme(bundleID: String) -> String {
        """
        # AndroidJNI bridge (generated by `swiftport sync`)

        Kotlin bindings: `src/main/java/\(bundleID.replacingOccurrences(of: ".", with: "/"))/bridge/SwiftPortBridge.kt`
        JNI shim: `src/main/cpp/jni_shim.c` → `libswiftport_jni.so` (built by
        the NDK/CMake hook in `Apps/Android/app/build.gradle.kts`).

        ## Producing libswiftportcore.so

        Requires the Swift Android SDK (https://www.swift.org/swift-android/):

        ```sh
        cd Core
        swift build -c release \\
            --swift-sdk aarch64-unknown-linux-android \\
            --product AppCoreCABI
        swift build -c release \\
            --swift-sdk x86_64-unknown-linux-android \\
            --product AppCoreCABI
        ```

        Then copy each `AppCoreCABI.so` to
        `Apps/Android/app/src/main/jniLibs/<abi>/libswiftportcore.so`
        (`arm64-v8a`, `x86_64`).

        ## Wire format

        Every bridge call returns the JSON encoding of `TaskListSnapshot`
        (Swift `Codable`, ISO-8601 dates, sorted keys) or null on failure.
        `snapshotFromFixture(json)` accepts a `Verification/Contracts/*.json`
        fixture verbatim — the deterministic path contract tests should use.
        """
    }

    // MARK: - C# / P/Invoke

    private static func csharpBridge(namespaceName: String) -> String {
        """
        // Generated by `swiftport sync` — do not edit.
        // P/Invoke bindings for the Swift `AppCoreCABI` library.
        // Strings cross as UTF-8; every call returns the JSON encoding of
        // `TaskListSnapshot` (or null on failure).
        using System;
        using System.Runtime.InteropServices;
        using System.Text.Json;
        using System.Text.Json.Serialization;

        namespace \(namespaceName)
        {
            /// <summary>Wire models mirroring the Swift Codable schema.</summary>
            public enum TaskPhase { Loading, Empty, Loaded, Error }

            public sealed class TaskItem
            {
                [JsonPropertyName("id")] public string Id { get; set; } = "";
                [JsonPropertyName("title")] public string Title { get; set; } = "";
                [JsonPropertyName("notes")] public string Notes { get; set; } = "";
                [JsonPropertyName("isCompleted")] public bool IsCompleted { get; set; }
                [JsonPropertyName("priority")] public string Priority { get; set; } = "medium";
                [JsonPropertyName("createdAt")] public string CreatedAt { get; set; } = "";
            }

            public sealed class TaskListSnapshot
            {
                [JsonPropertyName("phase")] public string Phase { get; set; } = "";
                [JsonPropertyName("tasks")] public List<TaskItem> Tasks { get; set; } = new();
                [JsonPropertyName("errorMessage")] public string? ErrorMessage { get; set; }
            }

            /// <summary>
            /// Calls into AppCoreCABI.dll (built from Core/ by
            /// `swift build` for the windows Swift SDK). The DLL must sit
            /// next to the app executable — see Apps/Windows README.
            /// </summary>
            public static class SwiftPortBridge
            {
                private const string Lib = "AppCoreCABI";

                [DllImport(Lib, CallingConvention = CallingConvention.Cdecl,
                           EntryPoint = "swiftport_abi_version")]
                private static extern int NativeAbiVersion();

                [DllImport(Lib, CallingConvention = CallingConvention.Cdecl,
                           EntryPoint = "swiftport_fixture_snapshot_json")]
                private static extern IntPtr NativeFixtureSnapshotJson(IntPtr fixtureJson);

                [DllImport(Lib, CallingConvention = CallingConvention.Cdecl,
                           EntryPoint = "swiftport_store_snapshot_json")]
                private static extern IntPtr NativeStoreSnapshotJson();

                [DllImport(Lib, CallingConvention = CallingConvention.Cdecl,
                           EntryPoint = "swiftport_store_add_task")]
                private static extern IntPtr NativeStoreAddTask(IntPtr title, IntPtr notes, IntPtr priority);

                [DllImport(Lib, CallingConvention = CallingConvention.Cdecl,
                           EntryPoint = "swiftport_store_toggle_task")]
                private static extern IntPtr NativeStoreToggleTask(IntPtr id);

                [DllImport(Lib, CallingConvention = CallingConvention.Cdecl,
                           EntryPoint = "swiftport_store_delete_task")]
                private static extern IntPtr NativeStoreDeleteTask(IntPtr id);

                [DllImport(Lib, CallingConvention = CallingConvention.Cdecl,
                           EntryPoint = "swiftport_store_reset")]
                private static extern IntPtr NativeStoreReset();

                [DllImport(Lib, CallingConvention = CallingConvention.Cdecl,
                           EntryPoint = "swiftport_free_string")]
                private static extern void NativeFreeString(IntPtr pointer);

                private static readonly JsonSerializerOptions JsonOptions = new()
                {
                    PropertyNameCaseInsensitive = true,
                };

                public static int AbiVersion() => NativeAbiVersion();

                /// Deterministic snapshot for a Verification/Contracts fixture.
                public static TaskListSnapshot? SnapshotFromFixture(string fixtureJson)
                {
                    IntPtr p = Marshal.StringToCoTaskMemUTF8(fixtureJson);
                    try { return Parse(NativeFixtureSnapshotJson(p)); }
                    finally { Marshal.FreeCoTaskMem(p); }
                }

                public static TaskListSnapshot? StoreSnapshot() => Parse(NativeStoreSnapshotJson());

                public static TaskListSnapshot? AddTask(string title, string notes = "", string priority = "medium")
                {
                    IntPtr t = Marshal.StringToCoTaskMemUTF8(title);
                    IntPtr n = Marshal.StringToCoTaskMemUTF8(notes);
                    IntPtr pr = Marshal.StringToCoTaskMemUTF8(priority);
                    try { return Parse(NativeStoreAddTask(t, n, pr)); }
                    finally
                    {
                        Marshal.FreeCoTaskMem(t);
                        Marshal.FreeCoTaskMem(n);
                        Marshal.FreeCoTaskMem(pr);
                    }
                }

                public static TaskListSnapshot? ToggleTask(string id)
                {
                    IntPtr p = Marshal.StringToCoTaskMemUTF8(id);
                    try { return Parse(NativeStoreToggleTask(p)); }
                    finally { Marshal.FreeCoTaskMem(p); }
                }

                public static TaskListSnapshot? DeleteTask(string id)
                {
                    IntPtr p = Marshal.StringToCoTaskMemUTF8(id);
                    try { return Parse(NativeStoreDeleteTask(p)); }
                    finally { Marshal.FreeCoTaskMem(p); }
                }

                public static TaskListSnapshot? ResetStore() => Parse(NativeStoreReset());

                private static TaskListSnapshot? Parse(IntPtr ptr)
                {
                    if (ptr == IntPtr.Zero) return null;
                    try
                    {
                        string? json = Marshal.PtrToStringUTF8(ptr);
                        return json == null ? null
                            : JsonSerializer.Deserialize<TaskListSnapshot>(json, JsonOptions);
                    }
                    finally
                    {
                        NativeFreeString(ptr);
                    }
                }
            }
        }
        """
    }

    private static func windowsReadme(bundleID: String) -> String {
        """
        # WindowsABI bridge (generated by `swiftport sync`)

        `SwiftPortBridge.cs` contains the C# wire models and P/Invoke
        declarations for the `swiftport_*` C ABI exported by
        `AppCoreCABI.dll`.

        ## Producing AppCoreCABI.dll

        On a Windows machine with the Swift toolchain:

        ```powershell
        cd Core
        swift build -c release --product AppCoreCABI
        ```

        Copy the resulting `AppCoreCABI.dll` next to the app executable
        (the WinUI csproj globs `Bridges/WindowsABI/**/*.dll` into the
        output directory — drop the DLL under `Bridges/WindowsABI/lib/`).

        ## Wire format

        Every bridge call returns the JSON encoding of `TaskListSnapshot`
        (Swift `Codable`, ISO-8601 dates, sorted keys) or null on failure.
        `SnapshotFromFixture(json)` accepts a `Verification/Contracts/*.json`
        fixture verbatim — the deterministic path contract tests should use.
        """
    }
}
