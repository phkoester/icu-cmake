# icu-cmake

icu-cmake adds a CMake build to [ICU4C](https://github.com/unicode-org/icu). It downloads the ICU release
sources, builds ICU's own data tools, generates the ICU data from the text sources, and produces these static
libraries:

| Linux           | Windows       | CMake target | Content
| :-------------- | :------------ | :----------- | :------
| `libicudata.a`  | `icudata.lib` | `ICU::data`  | The ICU data package (`icudtNNl`)
| `libicuuc.a`    | `icuuc.lib`   | `ICU::uc`    | Common library
| `libicui18n.a`  | `icui18n.lib` | `ICU::i18n`  | Internationalization library
| `libicuio.a`    | `icuio.lib`   | `ICU::io`    | Unicode stdio library
| `libicutu.a`    | `icutu.lib`   | `ICU::tu`    | Tool utilities

Supported toolchains: GCC and Clang on Linux, MSVC and clang-cl on Windows.

The project depends on [Gaia](https://github.com/phkoester/gaia), which provides the underlying build system
at shell level.

It is pre-alpha, a hobby project of mine, and possibly dangerous. **Use it at your own risk.**

## Prerequisites

- CMake 4.2 or later
- Python 3.8 or later (ICU's data build, `icutools.databuilder`, is written in Python)
- A C and C++ toolchain (C11, C++17)
- Internet access on first configure, unless local sources are supplied (see below)

## Building

With Gaia:

```sh
$ make build          # Configure and build
$ make test           # Run the smoke test
$ GAIA_CXX_TOOLCHAIN=llvm make build test
```

With plain CMake:

```sh
$ cmake --preset linux-release
$ cmake --build --preset linux-release
$ ctest --preset linux-release
$ cmake --install build/release --prefix /some/prefix
```

On Windows:

```sh
$ cmake --preset windows               # MSVC
$ cmake --preset windows -T ClangCL    # clang-cl
$ cmake --build --preset windows-release
```

## How It Works

1. The release archives `icu4c-VERSION-sources.tgz` and `icu4c-VERSION-data.zip` are downloaded with
   `FetchContent`. (Since ICU 68, the data text sources are no longer part of the sources archive.)
2. `common`, `i18n`, `io`, and `toolutil` are compiled into object libraries, using the `sources.txt` files
   ICU ships in each directory.
3. ICU's data tools (`genrb`, `makeconv`, `gencnval`, `genbrk`, `gencfu`, `gendict`, `gensprep`, `icupkg`,
   `pkgdata`, `genccode`) are built against the object libraries and the stub data library.
4. `python -m icutools.databuilder` runs the tools on the text sources, `pkgdata` packs the result into
   `icudtNNl.dat`, and `genccode` turns the archive into an assembly file (Linux), an object file (Windows),
   or a C file.
5. The static libraries are assembled from the object libraries and the generated data. `ICU::uc` links
   `ICU::data` publicly, so consumers never have to care about link order.

## Consuming

As an installed package:

```cmake
find_package(ICU 79.1 CONFIG REQUIRED COMPONENTS uc i18n)
target_link_libraries(my-target PRIVATE ICU::i18n)
```

Configure the consumer with `-DCMAKE_PREFIX_PATH=/some/prefix`. The package also defines `ICU_VERSION`,
`ICU_INCLUDE_DIRS`, `ICU_DATA_FILE` (the installed `.dat` file), and `ICU_<component>_FOUND`.

As a subproject:

```cmake
include(FetchContent)
FetchContent_Declare(icu-cmake GIT_REPOSITORY https://github.com/phkoester/icu-cmake.git GIT_TAG main)
FetchContent_MakeAvailable(icu-cmake)
target_link_libraries(my-target PRIVATE ICU::uc)
```

## Installed Layout

| Path                                | Content
| :---------------------------------- | :------
| `include/unicode/*.h`               | Public headers of `common`, `i18n`, and `io`
| `include/icu/toolutil/*.h`          | Headers of `toolutil`
| `lib/libicu*.a`, `lib/icu*.lib`     | The static libraries
| `lib/cmake/ICU/ICUConfig.cmake`     | Package configuration for `find_package(ICU CONFIG)`
| `share/icu/VERSION/icudtNNl.dat`    | The data archive, for runtime loading via `u_setDataDirectory`

## CMake Variables

| Name                            | Type       | Default                           | Description
| :------------------------------ | :--------- | :-------------------------------- | :----------
| `BUILD_TESTING`                 | `BOOL`     | `ON`                              | Enable testing and build tests
| `CMAKE_BUILD_TYPE`              | `STRING`   | `Release` if single configuration | The build type (`Debug` or `Release`)
| `ICU_CMAKE_BUILD_TEST`          | `BOOL`     | `ON` if master project            | Enable testing and build the smoke test
| `ICU_CMAKE_DATA_FILTER_FILE`    | `FILEPATH` | &mdash;                           | ICU [data filter file](https://unicode-org.github.io/icu/userguide/icu_data/buildtool.html) to reduce the data size
| `ICU_CMAKE_DATA_FORMAT`         | `STRING`   | `asm` (Linux), `object` (Windows) | How `genccode` emits the data: `asm`, `object`, or `c`
| `ICU_CMAKE_DATA_VERBOSE`        | `BOOL`     | `OFF`                             | Print every command of the ICU data build
| `ICU_CMAKE_ICU_DATA_HASH`       | `STRING`   | known for 79.1                    | Expected SHA-256 of the data archive (empty: skip check)
| `ICU_CMAKE_ICU_DATA_SOURCE_DIR` | `PATH`     | &mdash;                           | Local ICU data sources (`icu4c/source/data`) instead of downloading them
| `ICU_CMAKE_ICU_SOURCE_DIR`      | `PATH`     | &mdash;                           | Local ICU checkout (repository root, `icu4c`, or `icu4c/source`) instead of downloading
| `ICU_CMAKE_ICU_SOURCE_HASH`     | `STRING`   | known for 79.1                    | Expected SHA-256 of the sources archive (empty: skip check)
| `ICU_CMAKE_ICU_VERSION`         | `STRING`   | `79.1`                            | ICU version to download (`release-VERSION` tag; 78.1 or later use this naming scheme)
| `ICU_CMAKE_INSTALL`             | `BOOL`     | `ON` if master project            | Generate install rules and the CMake package configuration

A Git checkout of ICU contains the data sources, so `ICU_CMAKE_ICU_SOURCE_DIR` alone is sufficient in that
case. Variables may also be set via environment variables of the same name.

## Limitations

- Static libraries only (`BUILD_SHARED_LIBS` must be `OFF`).
- Little-endian targets only.
- No cross-compilation: the data tools must run on the build host.
- The `tzdata` override, ICU4J data, and the ICU test suites are not built.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  http://www.apache.org/licenses/LICENSE-2.0)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

## Third-Party Components

- [ICU](https://github.com/unicode-org/icu) ([license](license/ICU/LICENSE))
