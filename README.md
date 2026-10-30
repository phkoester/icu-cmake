# icu-cmake

icu-cmake adds a CMake build to [ICU4C](https://github.com/unicode-org/icu). It downloads the ICU4C release
source and data files, builds ICU's own data tools, generates the ICU data from the text sources, and
produces the libraries shown in the following table.

With `BUILD_SHARED_LIBS` left `OFF` they are static. With `BUILD_SHARED_LIBS` set to `ON` they are shared:
`.so` on Linux and DLL on Windows. A Windows shared build also writes import libraries (`.lib`) beside the
DLLs.

| Linux                             | Windows                        | CMake Target      | Content
| :-------------------------------- | :----------------------------- | :---------------- | :------
| `libicudata.a` or `libicudata.so` | `icudata.lib` or `icudata.dll` | `icu-cmake::data` | The ICU data package (`icudtNNl` or `icudtNNb`)
| `libicui18n.a` or `libicui18n.so` | `icui18n.lib` or `icui18n.dll` | `icu-cmake::i18n` | Internationalization library
| `libicuio.a` or `libicuio.so`     | `icuio.lib` or `icuio.dll`     | `icu-cmake::io`   | Unicode standard I/O library
| `libicutu.a` or `libicutu.so`     | `icutu.lib` or `icutu.dll`     | `icu-cmake::tu`   | Tool utilities
| `libicuuc.a` or `libicuuc.so`     | `icuuc.lib` or `icuuc.dll`     | `icu-cmake::uc`   | Common library

Supported C++ toolchains on Linux are GNU (`g++`) and LLVM (`clang`). On Windows, they are LLVM
(`clang-cl.exe`) and MSVC (`cl.exe`)

icu-cmake may be used out of the box. Just fetch the content and link to the desired targets. It's as simple
as that. See the [detailed instructions](#how-to-use-it-with-cmake).

## CMake Requirements

* CMake 4.2 or higher.
* Python 3.8 or higher. On Windows, both a native Windows Python and an MSYS Python will work.
* The Python package `semver`.
* On Windows, a Developer Command Prompt from Microsoft Visual Studio is required.

## How to Use It with CMake

Adding icu-cmake to your project is straightforward:

```cmake
include(FetchContent)

# Declare the repository
FetchContent_Declare(
  icu-cmake
  GIT_REPOSITORY https://github.com/phkoester/icu-cmake.git
  GIT_TAG        v0.1.1
)

# Select desired ICU version, fetch `icu-cmake` as a subproject
set(ICU_CMAKE_ICU_VERSION 79.1) # This is optional, `79.1` is the default
FetchContent_MakeAvailable(icu-cmake)

# Link the common library to your target. That's it!
target_link_libraries(my-target PRIVATE icu-cmake::uc)
```

## How It Works

1. The release archives `icu4c-VERSION-sources.tgz` and `icu4c-VERSION-data.zip` are downloaded with
   `FetchContent`. (Since ICU 68, the data text sources are no longer part of the sources archive.)
2. `common`, `i18n`, `io`, and `toolutil` are compiled into object libraries, using the `sources.txt` files
   ICU ships in each directory.
3. ICU's data tools (`genbrk`, `genccode`, `gencfu`, `gencnval`, `gendict`, `genrb`, `gensprep`, `icupkg`,
   `makeconv`, and `pkgdata`) are built against the object libraries and the stub data library.
4. `python -m icutools.databuilder` runs the tools on the text sources, `pkgdata` packs the result into
   `icudtNNl.dat` (little-endian) or `icudtNNb.dat` (big-endian), and `genccode` turns the archive into an
   assembly file (Linux), an object file (Windows), or a C file.
5. The libraries are assembled from the object libraries and the generated data. They are static unless
   `BUILD_SHARED_LIBS` is on. `icu-cmake::uc` links `icu-cmake::data` publicly, so consumers never have to
   care about link order. A static build publishes `U_STATIC_IMPLEMENTATION` through the library interface.

## CMake Options

All of the following options may be supplied either as defined CMake variables or as environment variables:

| Name                       | Type       | Default                           | Description
| :------------------------- | :--------- | :-------------------------------- | :----------
| `BUILD_SHARED_LIBS`        | `BOOL`     | `OFF`                             | Build shared libraries (`.so` on Linux, DLL on Windows) instead of static libraries
| `BUILD_TESTING`            | `BOOL`     | `ON`                              | Enable testing and build tests
| `CMAKE_BUILD_TYPE`         | `STRING`   | `Release` if single configuration | The build type (`Debug` or `Release`)
| `ICU_CMAKE_BUILD_ICU_TEST` | `BOOL`     | `ON` if master project            | Build the ICU tests
| `ICU_CMAKE_BUILD_TEST`     | `BOOL`     | `ON` if master project            | Build the unit tests
| `ICU_CMAKE_DATA_FORMAT`    | `STRING`   | `asm` (Linux), `object` (Windows) | How `genccode` emits the data: `asm`, `object`, or `c`
| `ICU_CMAKE_DATA_VERBOSE`   | `BOOL`     | `OFF`                             | Print every command of the ICU data build
| `ICU_CMAKE_ICU_VERSION`    | `STRING`   | `79.1`                            | ICU version to download (`release-VERSION` tag; 78.1 or later use this naming scheme)

## Limitations

- No cross-compilation: the data tools must run on the build host.
- The `tzdata` override and ICU4J data are not built.
- ICU's own tests are registered when `ICU_CMAKE_BUILD_ICU_TEST` is `ON`. Programs are discovered from the
  makefiles under `source/test`. `perf` benchmarks are not run by ICU's `check` target. `hdrtst`, `depstest`,
  and `letest` are not registered. `letest` needs the layout library, which this project does not build.
- `ICU_CMAKE_BUILD_TEST` builds a smoke test that checks the libraries link and that the real data is available.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  http://www.apache.org/licenses/LICENSE-2.0)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

## Third-Party Components

- [ICU](https://github.com/unicode-org/icu) ([license](license/ICU/LICENSE))
