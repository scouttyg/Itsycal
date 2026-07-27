//
//  EventQuickEntryParser.h
//  Itsycal
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Values match the index of the corresponding item in EventViewController's
// _repPopup (EventViewController.m): 0 = None, 1 = Every Day, 2 = Every Week,
// 3 = Every 2 Weeks, 4 = Every Month, 5 = Every Year.
typedef NS_ENUM(NSInteger, EventQuickEntryRecurrence) {
    EventQuickEntryRecurrenceNone        = 0,
    EventQuickEntryRecurrenceEveryDay    = 1,
    EventQuickEntryRecurrenceEveryWeek   = 2,
    EventQuickEntryRecurrenceEvery2Weeks = 3,
    EventQuickEntryRecurrenceEveryMonth  = 4,
    EventQuickEntryRecurrenceEveryYear   = 5,
};

// A stable, non-localized identifier for what kind of thing a span
// represents — distinct from `label`, which is display text. Consumers
// that need to branch on span type (e.g. picking a highlight color)
// should switch on `kind`, not compare `label` strings, since `label`
// is the one part of a span meant to vary by language pack.
typedef NS_ENUM(NSInteger, EventQuickEntrySpanKind) {
    EventQuickEntrySpanKindDate,
    EventQuickEntrySpanKindDuration,
    EventQuickEntrySpanKindLocation,
    EventQuickEntrySpanKindRepeat,
};

@interface EventQuickEntrySpan : NSObject
@property (nonatomic) NSRange range; // into the original input string
@property (nonatomic) EventQuickEntrySpanKind kind;
@property (nonatomic, copy) NSString *label;        // "Date", "Duration", "Location", "Repeat"
@property (nonatomic, copy) NSString *displayValue;  // human-readable interpreted value
@end

@interface EventQuickEntryResult : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, nullable) NSDate *date;
@property (nonatomic) BOOL hasExplicitTime;
@property (nonatomic) NSInteger durationMinutes; // 0 == not detected
@property (nonatomic, copy, nullable) NSString *location;
@property (nonatomic) EventQuickEntryRecurrence recurrence;
@property (nonatomic, copy) NSArray<EventQuickEntrySpan *> *recognizedSpans;
@end

// Implement this to add a new language. Each method receives the same
// "masked text" pipeline EventQuickEntryParser already uses: recognized
// ranges are blanked out (replaced with equal-length spaces) as each
// detector runs, so later detectors never re-match text an earlier one
// already claimed, and returned ranges stay valid throughout. A detector
// that finds nothing must return nil, not a zero-length span — every
// field this protocol can set (result.date, result.durationMinutes, etc.)
// is only applied by callers when a value was actually found.
//
// Most languages only need different *words*, not different matching
// logic — see EventQuickEntryKeywordLanguagePack, a generic implementation
// of this protocol driven by an EventQuickEntryKeywords config, which is
// almost certainly what you want. Implement this protocol directly only
// if your language's grammar doesn't fit that shape (e.g. no equivalent
// of English-style prepositions for location/time).
@protocol EventQuickEntryLanguagePack <NSObject>
// Example phrase shown as the quick-entry field's placeholder text, e.g.
// "Meeting with Bob for 30 min this Friday" (en).
@property (nonatomic, readonly, copy) NSString *placeholderExample;
- (nullable EventQuickEntrySpan *)dateSpanInMasked:(NSMutableString *)masked
                                           original:(NSString *)original
                                             result:(EventQuickEntryResult *)result
                                           calendar:(NSCalendar *)calendar;
- (nullable EventQuickEntrySpan *)durationSpanInMasked:(NSMutableString *)masked result:(EventQuickEntryResult *)result;
- (nullable EventQuickEntrySpan *)locationSpanInMasked:(NSMutableString *)masked result:(EventQuickEntryResult *)result;
- (nullable EventQuickEntrySpan *)recurrenceSpanInMasked:(NSMutableString *)masked result:(EventQuickEntryResult *)result;
@end

// The word/phrase lists that drive EventQuickEntryKeywordLanguagePack.
// A new keyword-based language pack only needs to supply one of these —
// no new matching logic. All arrays are case-insensitive whole-word/phrase
// matches; NSDataDetector's own date/time recognition (locale-aware,
// not configured here) still does the heavy lifting for the date itself.
@interface EventQuickEntryKeywords : NSObject
// BCP-47-ish language code, e.g. "en", "es". Used to localize the date
// formatter used for tooltip display text.
@property (nonatomic, copy) NSString *languageCode;
// The word before a duration phrase, e.g. "for" (en) / "durante" (es).
@property (nonatomic, copy) NSString *durationPrefixWord;
// The idiom for exactly 30 minutes, e.g. "half an hour" (en) / "media hora" (es).
@property (nonatomic, copy) NSString *halfHourPhrase;
// Idioms for exactly one hour, e.g. @[@"a hour", @"an hour"] (en) / @[@"una hora"] (es).
@property (nonatomic, copy) NSArray<NSString *> *oneHourPhrases;
// Words for "hours", e.g. @[@"hours", @"hour", @"hrs", @"hr"] (en) / @[@"horas", @"hora"] (es).
@property (nonatomic, copy) NSArray<NSString *> *hourUnitWords;
// Words for "minutes", e.g. @[@"minutes", @"minute", @"mins", @"min"] (en) / @[@"minutos", @"minuto"] (es).
@property (nonatomic, copy) NSArray<NSString *> *minuteUnitWords;
// Words introducing a location, e.g. @[@"at", @"in"] (en) / @[@"en", @"a"] (es).
// "@" is always recognized as a location prefix regardless of language.
@property (nonatomic, copy) NSArray<NSString *> *locationPrefixWords;
// Words that can precede a date/time reference without being part of it,
// so NSDataDetector's match (which never includes them) doesn't leave
// them stranded in the title — e.g. @[@"on"] (en) / @[@"el", @"la", @"esta", @"este"] (es).
@property (nonatomic, copy) NSArray<NSString *> *danglingPrefixWords;
// Meal words NSDataDetector may fold into its own date match as an
// implicit time-of-day reference, e.g. @[@"lunch", @"breakfast", @"dinner", @"brunch"] (en).
@property (nonatomic, copy) NSArray<NSString *> *mealWords;
// Non-numeric words that indicate NSDataDetector resolved an explicit
// time (beyond the universal digit+am/pm and digit:digit patterns, which
// are always recognized), e.g. @[@"noon", @"midnight", @"morning", @"afternoon", @"evening"] (en).
@property (nonatomic, copy) NSArray<NSString *> *explicitTimeWords;
// Phrases for each recurrence frequency. Keys are fixed and match
// EventQuickEntryRecurrence's non-None cases: "everyDay", "everyWeek",
// "every2Weeks", "everyMonth", "everyYear".
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<NSString *> *> *recurrencePhrasesByFrequencyKey;
// Display label for each recurrence frequency, same keys as above — must
// match the corresponding item title in EventViewController's _repPopup.
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *recurrenceLabelsByFrequencyKey;
// Category labels shown in span tooltips, e.g. "Date"/"Duration"/
// "Location"/"Repeat" (en) or "Fecha"/"Duración"/"Ubicación"/"Repetir" (es).
@property (nonatomic, copy) NSString *dateSpanLabel;
@property (nonatomic, copy) NSString *durationSpanLabel;
@property (nonatomic, copy) NSString *locationSpanLabel;
@property (nonatomic, copy) NSString *repeatSpanLabel;
// Word joining a date and time in the date span's tooltip display value,
// e.g. "Friday, January 2 <connector> 3:00 PM" — "at" (en) / "a las" (es).
@property (nonatomic, copy) NSString *dateTimeConnector;
// Example phrase shown as the quick-entry field's placeholder text.
@property (nonatomic, copy) NSString *placeholderExample;

// Loads keywords from a .strings file on disk with the shape shown by
// Base.lproj/EventQuickEntryKeywords.strings / es.lproj/EventQuickEntryKeywords.strings
// — the same flat "key" = "value"; format as Localizable.strings. Array-
// valued properties are a single pipe-delimited entry ("word1|word2");
// the two recurrence dictionaries are flattened into "recurrencePhrases.<key>"
// / "recurrenceLabel.<key>" entries, one per frequency. Returns nil if the
// file is missing or isn't a valid .strings file.
+ (nullable instancetype)keywordsWithContentsOfStringsFileAtPath:(NSString *)path;
// The fixed key order for recurrencePhrasesByFrequencyKey/
// recurrenceLabelsByFrequencyKey — every2Weeks is deliberately checked
// before everyWeek so "every other week"-style phrases aren't shadowed by
// the plain "every week" pattern.
+ (NSArray<NSString *> *)recurrenceFrequencyKeys;
@end

// Generic EventQuickEntryLanguagePack implementation driven entirely by
// an EventQuickEntryKeywords config — the matching *logic* (masked-text
// pipeline, regex shapes) is fixed; only the words are configurable. Every
// keyword-based language uses this same class directly, constructed from
// keywords loaded from that language's plist — see
// EventQuickEntryLanguagePackRegistry, which is how you actually get one.
@interface EventQuickEntryKeywordLanguagePack : NSObject <EventQuickEntryLanguagePack>
- (instancetype)initWithKeywords:(EventQuickEntryKeywords *)keywords NS_DESIGNATED_INITIALIZER;
// Shared utility available to any EventQuickEntryLanguagePack implementation
// (not just this base class) for the masked-text technique: replaces
// `range` in `masked` with spaces of the same length, so indices into the
// original string stay valid and later detectors never re-match it.
+ (void)blankRange:(NSRange)range inMasked:(NSMutableString *)masked;
@end

@interface EventQuickEntryLanguagePackRegistry : NSObject
// Returns the language pack for a BCP-47-ish language code (e.g. from
// -[NSBundle preferredLocalizations]), or nil if no pack is registered for
// it. A language is "registered" simply by the presence of an
// EventQuickEntryKeywords.strings resource in that language's <code>.lproj
// folder (English lives in Base.lproj, like the rest of the app's
// development-language resources) — the same localized-resource-variant
// mechanism already used for Localizable.strings/MainMenu.xib. Adding a
// new keyword-based language means adding a new .lproj/EventQuickEntryKeywords.strings
// file, not writing or compiling any code. Matches by primary language
// subtag, so "en-US"/"en-GB"/etc. all resolve to the "en" (Base) pack.
+ (nullable id<EventQuickEntryLanguagePack>)packForLanguageCode:(NSString *)languageCode;
@end

@interface EventQuickEntryParser : NSObject
// Convenience initializer using the English language pack.
- (instancetype)init;
- (instancetype)initWithLanguagePack:(id<EventQuickEntryLanguagePack>)languagePack NS_DESIGNATED_INITIALIZER;
// Parses free-form text into title/date/duration/location/recurrence.
// `calendar` is used for all date component arithmetic.
- (EventQuickEntryResult *)parse:(NSString *)text calendar:(NSCalendar *)calendar;
@end

NS_ASSUME_NONNULL_END
