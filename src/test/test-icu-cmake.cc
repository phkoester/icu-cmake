//
// test-icu-cmake.cc
//
// Smoke test: Checks that the ICU libraries link and that the real (non-stub) data is available.
//

#include <cstdio>
#include <cstring>
#include <string>

#include "unicode/ubrk.h"
#include "unicode/ucnv.h"
#include "unicode/unum.h"
#include "unicode/ures.h"
#include "unicode/ustdio.h"
#include "unicode/ustring.h"
#include "unicode/uvernum.h"
#include "unicode/uversion.h"

using namespace std;

namespace {

int failures = 0;

void
check(bool condition, const char* what) {
  printf("%s: %s\n", condition ? "PASS" : "FAIL", what);
  if (!condition) {
    ++failures;
  }
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

void
testVersion() {
  UVersionInfo info;
  char buffer[U_MAX_VERSION_STRING_LENGTH];
  u_getVersion(info);
  u_versionToString(info, buffer);
  printf("ICU version: %s\n", buffer);
  check(strcmp(buffer, U_ICU_VERSION) == 0, "u_getVersion matches U_ICU_VERSION");
}

void
testResourceBundle() {
  // Opening a locale bundle fails against the stub data, so this proves the real data is linked in
  UErrorCode status = U_ZERO_ERROR;
  UResourceBundle* bundle = ures_open(nullptr, "de", &status);
  check(U_SUCCESS(status) && status != U_USING_DEFAULT_WARNING && status != U_USING_FALLBACK_WARNING,
        "ures_open(\"de\") finds the German locale data");
  if (U_SUCCESS(status)) {
    int32_t length = 0;
    const UChar* name = ures_getStringByKey(bundle, "ExemplarCharacters", &length, &status);
    check(U_SUCCESS(status) && name != nullptr && length > 0, "ures_getStringByKey(\"ExemplarCharacters\")");
  }
  ures_close(bundle);
}

void
testNumberFormat() {
  UErrorCode status = U_ZERO_ERROR;
  UNumberFormat* format = unum_open(UNUM_DECIMAL, nullptr, 0, "de_DE", nullptr, &status);
  check(U_SUCCESS(status), "unum_open(\"de_DE\")");
  if (U_SUCCESS(status)) {
    UChar buffer[64];
    int32_t length = unum_formatDouble(format, 1234567.89, buffer, 64, nullptr, &status);
    string formatted = toUtf8(buffer, length);
    printf("Formatted number: %s\n", formatted.c_str());
    check(U_SUCCESS(status) && formatted == "1.234.567,89", "unum_formatDouble uses German separators");
  }
  unum_close(format);
}

void
testBreakIterator() {
  UErrorCode status = U_ZERO_ERROR;
  const UChar text[] = u"Hello wonderful world";
  UBreakIterator* iterator = ubrk_open(UBRK_WORD, "en_US", text, -1, &status);
  check(U_SUCCESS(status), "ubrk_open(UBRK_WORD)");
  if (U_SUCCESS(status)) {
    int words = 0;
    ubrk_first(iterator);
    while (ubrk_next(iterator) != UBRK_DONE) {
      if (ubrk_getRuleStatus(iterator) >= UBRK_WORD_LETTER) {
        ++words;
      }
    }
    printf("Words: %d\n", words);
    check(words == 3, "ubrk word iterator finds 3 words");
  }
  ubrk_close(iterator);
}

void
testConverter() {
  UErrorCode status = U_ZERO_ERROR;
  UConverter* converter = ucnv_open("ISO-8859-15", &status);
  check(U_SUCCESS(status), "ucnv_open(\"ISO-8859-15\") finds the converter data");
  ucnv_close(converter);
}

void
testIo() {
  UFILE* out = u_finit(stdout, nullptr, nullptr);
  check(out != nullptr, "u_finit(stdout)");
  if (out != nullptr) {
    int32_t written = u_fprintf(out, "u_fprintf: %d %S\n", 42, u"Grüße");
    check(written > 0, "u_fprintf writes");
    u_fclose(out);
  }
}

} // namespace

int
main() {
  testVersion();
  testResourceBundle();
  testNumberFormat();
  testBreakIterator();
  testConverter();
  testIo();

  printf("%d failure(s)\n", failures);
  return failures == 0 ? 0 : 1;
}

// EOF
