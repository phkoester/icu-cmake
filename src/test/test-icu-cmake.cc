/*
 * test-icu-cmake.cc
 *
 * Smoke test: Checks that the ICU libraries link and that the real (non-stub) data is available.
 *
 * This is a framework-less test executable. Each test is a plain function that records checks in a
 * `TestContext`. Every check is reported as it happens, and a summary is printed at the end. The exit code is
 * `EXIT_SUCCESS` if all checks pass, `EXIT_FAILURE` otherwise.
 *
 * Usage: `test-icu-cmake [--list] [TEST...]`. Without arguments, all tests are run; otherwise only the named
 * ones.
 */

#include "unicode/ubrk.h"
#include "unicode/uchar.h"
#include "unicode/uclean.h"
#include "unicode/ucnv.h"
#include "unicode/uloc.h"
#include "unicode/unum.h"
#include "unicode/ures.h"
#include "unicode/ustdio.h"
#include "unicode/ustring.h"
#include "unicode/uvernum.h"
#include "unicode/uversion.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <format>
#include <string>
#include <string_view>
#include <vector>

using namespace std;

namespace {

// Test infrastructure --------------------------------------------------------------------------------------

struct TestContext {
  int checks = 0;
  int failedChecks = 0;
};

using TestFunction = void (*)(TestContext&);

struct Test {
  const char* name;
  const char* description;
  TestFunction function;
};

void
info(string_view message) {
  printf("  [ INFO ] %.*s\n", static_cast<int>(message.size()), message.data());
}

// Records and reports a single check. `expression` is the stringified condition, `description` says what is
// being verified, in human terms
bool
check(TestContext& ctx, bool ok, const char* expression, string_view description, const char* file, int line) {
  ++ctx.checks;
  if (ok) {
    printf("  [  OK  ] %.*s\n", static_cast<int>(description.size()), description.data());
  } else {
    ++ctx.failedChecks;
    printf("  [ FAIL ] %.*s\n", static_cast<int>(description.size()), description.data());
    printf("           Condition `%s` is false at %s:%d\n", expression, file, line);
  }
  return ok;
}

// `CHECK(condition, format, args...)`: Records the check and continues
#define CHECK(condition, ...) \
  check(ctx, static_cast<bool>(condition), #condition, format(__VA_ARGS__), __FILE__, __LINE__)

// `REQUIRE(condition, format, args...)`: Records the check and returns from the test if it fails
#define REQUIRE(condition, ...) \
  do { \
    if (!check(ctx, static_cast<bool>(condition), #condition, format(__VA_ARGS__), __FILE__, __LINE__)) { \
      info("Skipping the rest of this test because a required check failed"); \
      return; \
    } \
  } while (false)

// Local functions ------------------------------------------------------------------------------------------

string
versionToString(const UVersionInfo versionInfo) {
  char buffer[U_MAX_VERSION_STRING_LENGTH];
  u_versionToString(versionInfo, buffer);
  return buffer;
}

void
printEnvironment() {
  UVersionInfo unicodeVersion;
  u_getUnicodeVersion(unicodeVersion);

  printf("test-icu-cmake: ICU smoke test\n");
  printf("  ICU version:     %s\n", U_ICU_VERSION);
  printf("  Unicode version: %s\n", versionToString(unicodeVersion).c_str());
  printf("  Data package:    %s\n", U_ICUDATA_NAME);
  printf("  Default locale:  %s\n", uloc_getDefault());
  printf("\n");
}

string
toUtf8(const UChar* s, int32_t length) {
  string out;
  UErrorCode status = U_ZERO_ERROR;
  int32_t outLength = 0;
  u_strToUTF8(nullptr, 0, &outLength, s, length, &status);
  status = U_ZERO_ERROR;
  out.resize(static_cast<size_t>(outLength));
  u_strToUTF8(out.data(), outLength, nullptr, s, length, &status);
  return U_SUCCESS(status) ? out : string();
}

} // namespace

// Tests ----------------------------------------------------------------------------------------------------

void
testInit(TestContext& ctx) {
  // `u_init` loads part of the ICU data and is meant as a check for configuration or installation problems
  UErrorCode status = U_ZERO_ERROR;
  u_init(&status);
  CHECK(U_SUCCESS(status), "u_init() succeeds (status: {})", u_errorName(status));
}

void
testVersion(TestContext& ctx) {
  UVersionInfo versionInfo;
  u_getVersion(versionInfo);
  string libraryVersion = versionToString(versionInfo);
  info(format("Header version: {}, library version: {}", U_ICU_VERSION, libraryVersion));
  CHECK(
    libraryVersion == U_ICU_VERSION,
    "u_getVersion() (\"{}\") matches U_ICU_VERSION (\"{}\")",
    libraryVersion,
    U_ICU_VERSION);
}

void
testBreakIterator(TestContext& ctx) {
  UErrorCode status = U_ZERO_ERROR;
  const UChar text[] = u"Hello wonderful world";
  UBreakIterator* iterator = ubrk_open(UBRK_WORD, "en_US", text, -1, &status);
  REQUIRE(U_SUCCESS(status), "ubrk_open(UBRK_WORD, \"en_US\") succeeds (status: {})", u_errorName(status));

  int words = 0;
  ubrk_first(iterator);
  while (ubrk_next(iterator) != UBRK_DONE) {
    if (ubrk_getRuleStatus(iterator) >= UBRK_WORD_LETTER) {
      ++words;
    }
  }
  ubrk_close(iterator);
  CHECK(words == 3, "Word iterator finds 3 words in \"Hello wonderful world\" (found: {})", words);
}

void
testConverter(TestContext& ctx) {
  UErrorCode status = U_ZERO_ERROR;
  UConverter* converter = ucnv_open("ISO-8859-15", &status);
  bool opened = CHECK(
    U_SUCCESS(status),
    "ucnv_open(\"ISO-8859-15\") finds the converter data (status: {})",
    u_errorName(status));
  if (opened) {
    info(format(
      "Converter name: {}, known converters: {}",
      ucnv_getName(converter, &status),
      ucnv_countAvailable()));

    // Convert the euro sign, which is 0xA4 in ISO-8859-15
    status = U_ZERO_ERROR;
    char buffer[8] = {};
    int32_t length = ucnv_fromUChars(converter, buffer, sizeof(buffer), u"\u20AC", -1, &status);
    CHECK(U_SUCCESS(status), "ucnv_fromUChars(\"\\u20AC\") succeeds (status: {})", u_errorName(status));
    CHECK(
      length == 1 && static_cast<unsigned char>(buffer[0]) == 0xA4,
      "U+20AC converts to the single byte 0xA4 (got {} byte(s), first: 0x{:02X})",
      length,
      static_cast<unsigned char>(buffer[0]));
  }
  ucnv_close(converter);
}

void
testIo(TestContext& ctx) {
  fflush(stdout); // `UFILE` writes through `stdout`, keep the output ordered
  UFILE* out = u_finit(stdout, nullptr, nullptr);
  REQUIRE(out != nullptr, "u_finit(stdout) returns a UFILE");
  info("Writing a line with u_fprintf:");
  int32_t written = u_fprintf(out, "           u_fprintf: %d %S\n", 42, u"Grüße");
  u_fclose(out); // Flushes, but does not close `stdout`, which `u_finit` does not own
  CHECK(written > 0, "u_fprintf() writes to stdout ({} UChars written)", written);
}

void
testResourceBundle(TestContext& ctx) {
  // Opening a locale bundle fails against the stub data, so this proves the real data is linked in
  UErrorCode status = U_ZERO_ERROR;
  UResourceBundle* bundle = ures_open(nullptr, "de", &status);
  REQUIRE(U_SUCCESS(status), "ures_open(nullptr, \"de\") succeeds (status: {})", u_errorName(status));
  CHECK(
    status != U_USING_DEFAULT_WARNING && status != U_USING_FALLBACK_WARNING,
    "ures_open(\"de\") finds the German locale data itself, not a fallback (status: {})",
    u_errorName(status));

  status = U_ZERO_ERROR;
  int32_t length = 0;
  const UChar* exemplars = ures_getStringByKey(bundle, "ExemplarCharacters", &length, &status);
  CHECK(
    U_SUCCESS(status),
    "ures_getStringByKey(\"ExemplarCharacters\") succeeds (status: {})",
    u_errorName(status));
  if (CHECK(
    exemplars != nullptr && length > 0,
    "German exemplar characters are non-empty (length: {})",
    length)) {
    info(format("German exemplar characters: {}", toUtf8(exemplars, length)));
  }
  ures_close(bundle);
}

void
testNumberFormat(TestContext& ctx) {
  UErrorCode status = U_ZERO_ERROR;
  UNumberFormat* numberFormat = unum_open(UNUM_DECIMAL, nullptr, 0, "de_DE", nullptr, &status);
  REQUIRE(
    U_SUCCESS(status),
    "unum_open(UNUM_DECIMAL, \"de_DE\") succeeds (status: {})",
    u_errorName(status));

  UChar buffer[64];
  int32_t length = unum_formatDouble(numberFormat, 1234567.89, buffer, 64, nullptr, &status);
  unum_close(numberFormat);
  CHECK(U_SUCCESS(status), "unum_formatDouble(1234567.89) succeeds (status: {})", u_errorName(status));
  string formatted = U_SUCCESS(status) ? toUtf8(buffer, length) : string();
  CHECK(formatted == "1.234.567,89", "German formatting yields \"1.234.567,89\" (got: \"{}\")", formatted);
}

// Test registry --------------------------------------------------------------------------------------------

const Test tests[] = {
  { "Init", "u_init() loads the ICU data", testInit },
  { "Version", "Library version matches the headers", testVersion },
  { "BreakIterator", "Word break iteration (break rules data)", testBreakIterator },
  { "Converter", "Charset conversion (converter data)", testConverter },
  { "Io", "Unicode stdio via the io library", testIo },
  { "ResourceBundle", "Locale resource bundles (locale data)", testResourceBundle },
  { "NumberFormat", "Locale-aware number formatting (i18n library)", testNumberFormat },
};

// `main` ---------------------------------------------------------------------------------------------------

int
main(int argc, char* argv[]) {
  // Select the tests

  vector<const Test*> selected;
  for (int i = 1; i < argc; ++i) {
    string_view arg = argv[i];
    if (arg == "--list") {
      for (const Test& test : tests) {
        printf("%-16s %s\n", test.name, test.description);
      }
      return EXIT_SUCCESS;
    }
    const Test* found = nullptr;
    for (const Test& test : tests) {
      if (arg == test.name) {
        found = &test;
      }
    }
    if (found == nullptr) {
      fprintf(stderr, "test-icu-cmake: Unknown test `%s`, use `--list` to see all tests\n", argv[i]);
      return EXIT_FAILURE;
    }
    selected.push_back(found);
  }
  if (selected.empty()) {
    for (const Test& test : tests) {
      selected.push_back(&test);
    }
  }

  printEnvironment();

  // Run the tests

  int totalChecks = 0;
  int totalFailedChecks = 0;
  vector<const char*> failedTests;
  auto start = chrono::steady_clock::now();

  for (size_t i = 0; i < selected.size(); ++i) {
    const Test& test = *selected[i];
    printf("[%zu/%zu] %s: %s\n", i + 1, selected.size(), test.name, test.description);
    fflush(stdout);

    TestContext ctx;
    bool threw = false;
    auto testStart = chrono::steady_clock::now();
    try {
      test.function(ctx);
    } catch (const exception& e) {
      threw = true;
      printf("  [ FAIL ] Unexpected exception: %s\n", e.what());
    } catch (...) {
      threw = true;
      printf("  [ FAIL ] Unexpected exception of unknown type\n");
    }
    auto ms = chrono::duration_cast<chrono::milliseconds>(chrono::steady_clock::now() - testStart).count();

    bool passed = !threw && ctx.failedChecks == 0;
    if (ctx.checks == 0 && !threw) {
      printf("  [ FAIL ] Test made no checks\n");
      passed = false;
    }
    printf(
      "  => %s (%d/%d checks passed, %lld ms)\n\n",
      passed ? "PASSED" : "FAILED",
      ctx.checks - ctx.failedChecks,
      ctx.checks,
      static_cast<long long>(ms));
    fflush(stdout);

    totalChecks += ctx.checks;
    totalFailedChecks += ctx.failedChecks;
    if (!passed) {
      failedTests.push_back(test.name);
    }
  }

  // Print the summary

  auto totalMs = chrono::duration_cast<chrono::milliseconds>(chrono::steady_clock::now() - start).count();
  size_t passedTests = selected.size() - failedTests.size();
  printf(
    "Summary: %zu/%zu tests passed, %d/%d checks passed (%lld ms)\n",
    passedTests,
    selected.size(),
    totalChecks - totalFailedChecks,
    totalChecks,
    static_cast<long long>(totalMs));
  if (failedTests.empty()) {
    printf("All tests PASSED\n");
  } else {
    printf("FAILED tests:\n");
    for (const char* name : failedTests) {
      printf("  - %s\n", name);
    }
  }
  fflush(stdout);

  u_cleanup();
  return failedTests.empty() ? EXIT_SUCCESS : EXIT_FAILURE;
}

// EOF
