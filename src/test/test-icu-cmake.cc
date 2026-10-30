/*
 * test-icu-cmake.cc
 *
 * Smoke test: Checks that the ICU libraries link and that the real (non-stub) data is available.
 */

#include <gtest/gtest.h>

#include "unicode/ubrk.h"
#include "unicode/ucnv.h"
#include "unicode/unum.h"
#include "unicode/ures.h"
#include "unicode/ustdio.h"
#include "unicode/ustring.h"
#include "unicode/uvernum.h"
#include "unicode/uversion.h"

#include <cstdio>
#include <string>

using namespace std;

namespace {

// Local functions ------------------------------------------------------------------------------------------

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

// `TEST` ---------------------------------------------------------------------------------------------------

TEST(icu, BreakIterator) {
  UErrorCode status = U_ZERO_ERROR;
  const UChar text[] = u"Hello wonderful world";
  UBreakIterator* iterator = ubrk_open(UBRK_WORD, "en_US", text, -1, &status);
  ASSERT_TRUE(U_SUCCESS(status)) << "ubrk_open(UBRK_WORD): " << u_errorName(status);

  int words = 0;
  ubrk_first(iterator);
  while (ubrk_next(iterator) != UBRK_DONE) {
    if (ubrk_getRuleStatus(iterator) >= UBRK_WORD_LETTER) {
      ++words;
    }
  }
  EXPECT_EQ(words, 3) << "ubrk word iterator finds 3 words";
  ubrk_close(iterator);
}

TEST(icu, Converter) {
  UErrorCode status = U_ZERO_ERROR;
  UConverter* converter = ucnv_open("ISO-8859-15", &status);
  EXPECT_TRUE(U_SUCCESS(status)) << "ucnv_open(\"ISO-8859-15\") finds the converter data: "
                                 << u_errorName(status);
  ucnv_close(converter);
}

TEST(icu, Io) {
  UFILE* out = u_finit(stdout, nullptr, nullptr);
  ASSERT_NE(out, nullptr) << "u_finit(stdout)";
  int32_t written = u_fprintf(out, "u_fprintf: %d %S\n", 42, u"Grüße");
  EXPECT_GT(written, 0) << "u_fprintf writes";
  u_fclose(out);
}

TEST(icu, ResourceBundle) {
  // Opening a locale bundle fails against the stub data, so this proves the real data is linked in
  UErrorCode status = U_ZERO_ERROR;
  UResourceBundle* bundle = ures_open(nullptr, "de", &status);
  ASSERT_TRUE(U_SUCCESS(status)) << "ures_open(\"de\"): " << u_errorName(status);
  EXPECT_NE(status, U_USING_DEFAULT_WARNING) << "ures_open(\"de\") finds the German locale data";
  EXPECT_NE(status, U_USING_FALLBACK_WARNING) << "ures_open(\"de\") finds the German locale data";

  int32_t length = 0;
  const UChar* name = ures_getStringByKey(bundle, "ExemplarCharacters", &length, &status);
  EXPECT_TRUE(U_SUCCESS(status)) << "ures_getStringByKey(\"ExemplarCharacters\"): " << u_errorName(status);
  EXPECT_NE(name, nullptr);
  EXPECT_GT(length, 0);
  ures_close(bundle);
}

TEST(icu, NumberFormat) {
  UErrorCode status = U_ZERO_ERROR;
  UNumberFormat* format = unum_open(UNUM_DECIMAL, nullptr, 0, "de_DE", nullptr, &status);
  ASSERT_TRUE(U_SUCCESS(status)) << "unum_open(\"de_DE\"): " << u_errorName(status);

  UChar buffer[64];
  int32_t length = unum_formatDouble(format, 1234567.89, buffer, 64, nullptr, &status);
  EXPECT_TRUE(U_SUCCESS(status)) << "unum_formatDouble: " << u_errorName(status);
  EXPECT_EQ(toUtf8(buffer, length), "1.234.567,89") << "unum_formatDouble uses German separators";
  unum_close(format);
}

TEST(icu, Version) {
  UVersionInfo info;
  char buffer[U_MAX_VERSION_STRING_LENGTH];
  u_getVersion(info);
  u_versionToString(info, buffer);
  EXPECT_STREQ(buffer, U_ICU_VERSION) << "u_getVersion matches U_ICU_VERSION";
}

// EOF
