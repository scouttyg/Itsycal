//
//  EventQuickEntryKeywords.m
//  Itsycal
//
//  Created by Scott Goci on 7/27/26.
//

#import "EventQuickEntryKeywords.h"
#import "EventQuickEntryParser.h"

@implementation EventQuickEntryKeywords

// Fixed key order for the two recurrence dictionaries, both here and in
// EventQuickEntryKeywordLanguagePack's regex construction — must match
// EventQuickEntryRecurrence's non-None cases.
+ (NSArray<NSString *> *)recurrenceFrequencyKeys
{
    return @[@"every2Weeks", @"everyDay", @"everyWeek", @"everyMonth", @"everyYear"];
}

+ (NSArray<NSString *> *)arrayForDelimitedString:(nullable NSString *)value
{
    if (value.length == 0) return @[];
    return [value componentsSeparatedByString:@"|"];
}

+ (nullable instancetype)keywordsWithContentsOfStringsFileAtPath:(NSString *)path
{
    NSDictionary<NSString *, NSString *> *strings = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!strings) return nil;

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *recurrencePhrases = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSString *> *recurrenceLabels = [NSMutableDictionary new];
    for (NSString *key in [self recurrenceFrequencyKeys]) {
        recurrencePhrases[key] = [self arrayForDelimitedString:strings[[@"recurrencePhrases." stringByAppendingString:key]]];
        recurrenceLabels[key] = strings[[@"recurrenceLabel." stringByAppendingString:key]] ?: @"";
    }

    EventQuickEntryKeywords *keywords = [EventQuickEntryKeywords new];
    keywords.languageCode = strings[@"languageCode"];
    keywords.durationPrefixWord = strings[@"durationPrefixWord"];
    keywords.halfHourPhrase = strings[@"halfHourPhrase"];
    keywords.oneHourPhrases = [self arrayForDelimitedString:strings[@"oneHourPhrases"]];
    keywords.hourUnitWords = [self arrayForDelimitedString:strings[@"hourUnitWords"]];
    keywords.minuteUnitWords = [self arrayForDelimitedString:strings[@"minuteUnitWords"]];
    keywords.locationPrefixWords = [self arrayForDelimitedString:strings[@"locationPrefixWords"]];
    keywords.danglingPrefixWords = [self arrayForDelimitedString:strings[@"danglingPrefixWords"]];
    keywords.mealWords = [self arrayForDelimitedString:strings[@"mealWords"]];
    keywords.explicitTimeWords = [self arrayForDelimitedString:strings[@"explicitTimeWords"]];
    keywords.recurrencePhrasesByFrequencyKey = recurrencePhrases;
    keywords.recurrenceLabelsByFrequencyKey = recurrenceLabels;
    keywords.dateSpanLabel = strings[@"dateSpanLabel"];
    keywords.durationSpanLabel = strings[@"durationSpanLabel"];
    keywords.locationSpanLabel = strings[@"locationSpanLabel"];
    keywords.repeatSpanLabel = strings[@"repeatSpanLabel"];
    keywords.dateTimeConnector = strings[@"dateTimeConnector"];
    keywords.placeholderExample = strings[@"placeholderExample"];
    return keywords;
}

@end

#pragma mark -
#pragma mark EventQuickEntryKeywordLanguagePack

@implementation EventQuickEntryKeywordLanguagePack
{
    EventQuickEntryKeywords *_keywords;
    NSRegularExpression *_timeRegex;
    NSRegularExpression *_durationRegex;
    NSRegularExpression *_mealWordRegex;        // nil if no meal words configured
    NSRegularExpression *_danglingPrefixRegex;  // nil if no dangling words configured
    NSRegularExpression *_locationPrefixRegex;
    NSRegularExpression *_trailingLocationPrefixRegex;
    NSArray<NSRegularExpression *> *_recurrenceRegexes; // ordered: every2Weeks, everyDay, everyWeek, everyMonth, everyYear
    NSArray<NSNumber *> *_recurrenceValues;             // parallel EventQuickEntryRecurrence values
    NSArray<NSString *> *_recurrenceLabels;             // parallel display labels
}

- (instancetype)initWithKeywords:(EventQuickEntryKeywords *)keywords
{
    self = [super init];
    if (self) {
        _keywords = keywords;
        [self buildTimeRegexFromKeywords:keywords];
        [self buildDurationRegexFromKeywords:keywords];
        [self buildMealWordRegexFromKeywords:keywords];
        [self buildDanglingPrefixRegexFromKeywords:keywords];
        [self buildLocationRegexFromKeywords:keywords];
        [self buildRecurrenceRegexesFromKeywords:keywords];
    }
    return self;
}

#pragma mark -
#pragma mark Regex construction

// Returns nil (not an empty string) when `phrases` is empty. This matters:
// an empty alternation group like `(?:)` is valid regex syntax that matches
// the *empty string* at every position, so silently interpolating "" into
// a larger pattern turns "this branch should never match" into "this
// branch matches almost anything" — e.g. an empty oneHourPhrases list
// would otherwise make `\bfor\s+()\b` match any "for <word>", not just
// "for a hour"/"for an hour". Every call site must explicitly decide what
// an absent word list means for its pattern (see the two call sites below
// for the two valid answers: omit the whole branch, or substitute "(?!)",
// a group that can never match, to keep capture-group numbering fixed).
+ (nullable NSString *)alternationPatternForPhrases:(NSArray<NSString *> *)phrases
{
    if (phrases.count == 0) return nil;
    NSMutableArray<NSString *> *escaped = [NSMutableArray new];
    for (NSString *phrase in phrases) {
        [escaped addObject:[NSRegularExpression escapedPatternForString:phrase]];
    }
    return [escaped componentsJoinedByString:@"|"];
}

- (void)buildTimeRegexFromKeywords:(EventQuickEntryKeywords *)keywords
{
    // The digit-based patterns are universal (digits are digits regardless
    // of language); only the non-numeric time-of-day words vary. No
    // explicitTimeWords configured just means that whole alternative is
    // omitted — the universal digit patterns still work.
    NSString *wordsAlt = [[self class] alternationPatternForPhrases:keywords.explicitTimeWords];
    NSString *wordsBranch = wordsAlt ? [NSString stringWithFormat:@"|\\b(?:%@)\\b", wordsAlt] : @"";
    NSString *pattern = [NSString stringWithFormat:@"(?i)\\b\\d{1,2}(:\\d{2})?\\s*(am|pm|a\\.m\\.|p\\.m\\.)\\b|\\b\\d{1,2}:\\d{2}\\b%@", wordsBranch];
    _timeRegex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
}

- (void)buildDurationRegexFromKeywords:(EventQuickEntryKeywords *)keywords
{
    if (keywords.durationPrefixWord.length == 0) {
        _durationRegex = nil;
        return;
    }
    NSString *forWord = [NSRegularExpression escapedPatternForString:keywords.durationPrefixWord];

    // Each alternative's word list is independently optional, but unlike
    // buildTimeRegexFromKeywords: above, a missing one can't just be
    // omitted here — -durationSpanInMasked:result: reads specific capture
    // group *indices* (1=half-hour, 2=one-hour, 3=hours, 4=minutes) to
    // classify which alternative matched, so all four must stay
    // structurally present. A missing word list instead gets "(?!)" — a
    // group that can never match — so that alternative is effectively
    // disabled without shifting the others' group numbers.
    NSString *halfHour = keywords.halfHourPhrase.length > 0
        ? [NSRegularExpression escapedPatternForString:keywords.halfHourPhrase]
        : @"(?!)";
    NSString *oneHourAlt = [[self class] alternationPatternForPhrases:keywords.oneHourPhrases] ?: @"(?!)";
    NSString *hourUnitAlt = [[self class] alternationPatternForPhrases:keywords.hourUnitWords] ?: @"(?!)";
    NSString *minuteUnitAlt = [[self class] alternationPatternForPhrases:keywords.minuteUnitWords] ?: @"(?!)";

    NSString *pattern = [NSString stringWithFormat:
        @"(?i)\\b%@\\s+(%@)\\b|\\b%@\\s+(%@)\\b|\\b%@\\s+(\\d+)\\s*(?:%@)\\b|\\b%@\\s+(\\d+)\\s*(?:%@)\\b",
        forWord, halfHour, forWord, oneHourAlt, forWord, hourUnitAlt, forWord, minuteUnitAlt];
    _durationRegex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
}

- (void)buildMealWordRegexFromKeywords:(EventQuickEntryKeywords *)keywords
{
    if (keywords.mealWords.count == 0) {
        _mealWordRegex = nil;
        return;
    }
    NSString *alt = [[self class] alternationPatternForPhrases:keywords.mealWords];
    NSString *pattern = [NSString stringWithFormat:@"(?i)^\\b(?:%@)\\b\\s*", alt];
    _mealWordRegex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
}

- (void)buildDanglingPrefixRegexFromKeywords:(EventQuickEntryKeywords *)keywords
{
    if (keywords.danglingPrefixWords.count == 0) {
        _danglingPrefixRegex = nil;
        return;
    }
    NSString *alt = [[self class] alternationPatternForPhrases:keywords.danglingPrefixWords];
    NSString *pattern = [NSString stringWithFormat:@"(?i)\\b(?:%@)\\s+$", alt];
    _danglingPrefixRegex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
}

- (void)buildLocationRegexFromKeywords:(EventQuickEntryKeywords *)keywords
{
    // "@" is always recognized as a location prefix regardless of language,
    // so locationPrefixWords is optional — a language pack with none still
    // works via "@" alone. The word-alternatives are wrapped in \b so the
    // boundary doesn't apply to "@" itself (a non-word character can't be
    // preceded by \b the way "@ Cafe Luna" needs it to).
    //
    // This only matches the prefix word itself, not the location phrase
    // that follows — see -locationSpanInMasked:original:result: for why: a
    // regex working on `masked` alone can't tell "more location text"
    // apart from a previously-blanked span's leftover spaces, since both
    // look like plain whitespace. Telling them apart needs a comparison
    // against `original`, which a regex can't express.
    NSString *prefixAlt = [[self class] alternationPatternForPhrases:keywords.locationPrefixWords];
    NSString *prefixGroup = prefixAlt ? [NSString stringWithFormat:@"\\b(?:%@)|@", prefixAlt] : @"@";
    NSString *pattern = [NSString stringWithFormat:@"(?i)(?:%@)\\s+", prefixGroup];
    _locationPrefixRegex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];

    // Matches a prefix word sitting at the very end of a string, with the
    // whitespace that separates it from real place text before it — used
    // to detect and trim a leftover dangling preposition off the tail of
    // an already-walked location range. See
    // -placeCoreEndByTrimmingDanglingPrefixFromMasked:range:.
    NSString *trailingPattern = [NSString stringWithFormat:@"(?i)\\s+(?:%@)$", prefixGroup];
    _trailingLocationPrefixRegex = [NSRegularExpression regularExpressionWithPattern:trailingPattern options:0 error:nil];
}

- (void)buildRecurrenceRegexesFromKeywords:(EventQuickEntryKeywords *)keywords
{
    // "every other week"-style phrases are checked before the plain
    // "every week"-style pattern so they aren't shadowed by it.
    NSArray<NSString *> *orderedKeys = [EventQuickEntryKeywords recurrenceFrequencyKeys];
    NSArray<NSNumber *> *orderedValues = @[
        @(EventQuickEntryRecurrenceEvery2Weeks),
        @(EventQuickEntryRecurrenceEveryDay),
        @(EventQuickEntryRecurrenceEveryWeek),
        @(EventQuickEntryRecurrenceEveryMonth),
        @(EventQuickEntryRecurrenceEveryYear),
    ];
    NSMutableArray<NSRegularExpression *> *regexes = [NSMutableArray new];
    NSMutableArray<NSNumber *> *values = [NSMutableArray new];
    NSMutableArray<NSString *> *labels = [NSMutableArray new];
    for (NSInteger i = 0; i < (NSInteger)orderedKeys.count; i++) {
        NSString *key = orderedKeys[i];
        NSArray<NSString *> *phrases = keywords.recurrencePhrasesByFrequencyKey[key];
        // A frequency with no configured phrases is skipped entirely,
        // rather than built into `\b(?:)\b` — which, since an empty
        // alternation group matches the empty string, would match at
        // *every* word boundary in *any* input (see
        // +alternationPatternForPhrases:). regexes/values/labels are
        // appended together so they stay index-parallel despite the skip.
        NSString *alt = [[self class] alternationPatternForPhrases:phrases];
        if (!alt) continue;
        NSString *pattern = [NSString stringWithFormat:@"(?i)\\b(?:%@)\\b", alt];
        [regexes addObject:[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil]];
        [values addObject:orderedValues[i]];
        [labels addObject:keywords.recurrenceLabelsByFrequencyKey[key] ?: @""];
    }
    _recurrenceRegexes = regexes;
    _recurrenceValues = values;
    _recurrenceLabels = labels;
}

#pragma mark -
#pragma mark EventQuickEntryLanguagePack — placeholder

- (NSString *)placeholderExample
{
    return _keywords.placeholderExample;
}

#pragma mark -
#pragma mark Shared masking utility

+ (void)blankRange:(NSRange)range inMasked:(NSMutableString *)masked
{
    NSString *blank = [@"" stringByPaddingToLength:range.length withString:@" " startingAtIndex:0];
    [masked replaceCharactersInRange:range withString:blank];
}

#pragma mark -
#pragma mark EventQuickEntryLanguagePack — Date/time

- (nullable EventQuickEntrySpan *)dateSpanInMasked:(NSMutableString *)masked original:(NSString *)original result:(EventQuickEntryResult *)result calendar:(NSCalendar *)calendar
{
    NSError *error = nil;
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:&error];
    if (!detector) return nil;

    NSTextCheckingResult *match = [detector firstMatchInString:original
                                                        options:0
                                                          range:NSMakeRange(0, original.length)];
    if (!match || !match.date) return nil;

    result.date = match.date;
    NSString *matchedText = [original substringWithRange:match.range];
    result.hasExplicitTime = [self textContainsExplicitTime:matchedText];

    // NSDataDetector computes a duration for time-range phrases like
    // "3-4pm". Set it here so an explicit "for X minutes"-style phrase
    // (handled by -durationSpanInMasked:result:) can still unconditionally
    // override it, since it runs later in the pipeline.
    if (match.duration > 0) {
        result.durationMinutes = (NSInteger)round(match.duration / 60.0);
    }

    NSRange rangeToBlank = [self rangeToBlankForDateMatch:match inOriginal:original];
    [[self class] blankRange:rangeToBlank inMasked:masked];

    EventQuickEntrySpan *span = [EventQuickEntrySpan new];
    span.range = rangeToBlank;
    span.kind = EventQuickEntrySpanKindDate;
    span.label = _keywords.dateSpanLabel;
    span.displayValue = [self displayValueForDate:result.date hasExplicitTime:result.hasExplicitTime calendar:calendar];
    return span;
}

// NSDataDetector's own match range doesn't always line up with what should
// actually be blanked out of the title: it sometimes folds a leading meal
// word into its own match as a time-of-day reference, and it never
// includes a dangling leading word (e.g. English "on", Spanish "el"/"esta")
// that precedes the match. This adjusts for both before anything is blanked.
- (NSRange)rangeToBlankForDateMatch:(NSTextCheckingResult *)match inOriginal:(NSString *)original
{
    NSRange coreRange = match.range;
    if (_mealWordRegex) {
        NSTextCheckingResult *mealMatch = [_mealWordRegex firstMatchInString:original options:0 range:match.range];
        if (mealMatch) {
            NSUInteger newLocation = NSMaxRange(mealMatch.range);
            coreRange = NSMakeRange(newLocation, NSMaxRange(match.range) - newLocation);
        }
    }

    NSRange rangeToBlank = coreRange;
    if (_danglingPrefixRegex) {
        NSTextCheckingResult *danglingMatch = [_danglingPrefixRegex firstMatchInString:original
                                                                                 options:0
                                                                                   range:NSMakeRange(0, coreRange.location)];
        if (danglingMatch) {
            rangeToBlank = NSMakeRange(danglingMatch.range.location, NSMaxRange(coreRange) - danglingMatch.range.location);
        }
    }
    return rangeToBlank;
}

- (NSString *)displayValueForDate:(NSDate *)date hasExplicitTime:(BOOL)hasExplicitTime calendar:(NSCalendar *)calendar
{
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:_keywords.languageCode];

    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    dateFormatter.calendar = calendar;
    dateFormatter.locale = locale;
    [dateFormatter setLocalizedDateFormatFromTemplate:@"EEEEMMMMd"];
    NSString *dateString = [dateFormatter stringFromDate:date];

    if (!hasExplicitTime) return dateString;

    NSDateFormatter *timeFormatter = [NSDateFormatter new];
    timeFormatter.calendar = calendar;
    timeFormatter.locale = locale;
    timeFormatter.dateStyle = NSDateFormatterNoStyle;
    timeFormatter.timeStyle = NSDateFormatterShortStyle;
    NSString *timeString = [timeFormatter stringFromDate:date];

    return [NSString stringWithFormat:@"%@ %@ %@", dateString, _keywords.dateTimeConnector, timeString];
}

- (BOOL)textContainsExplicitTime:(NSString *)text
{
    return [_timeRegex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

#pragma mark -
#pragma mark EventQuickEntryLanguagePack — Duration

- (nullable EventQuickEntrySpan *)durationSpanInMasked:(NSMutableString *)masked result:(EventQuickEntryResult *)result
{
    NSTextCheckingResult *match = [_durationRegex firstMatchInString:masked options:0 range:NSMakeRange(0, masked.length)];
    if (!match) return nil;

    NSInteger minutes = 0;
    if (match.numberOfRanges > 1 && [match rangeAtIndex:1].location != NSNotFound) {
        minutes = 30; // half-hour idiom
    } else if (match.numberOfRanges > 2 && [match rangeAtIndex:2].location != NSNotFound) {
        minutes = 60; // one-hour idiom
    } else if (match.numberOfRanges > 3 && [match rangeAtIndex:3].location != NSNotFound) {
        minutes = [[masked substringWithRange:[match rangeAtIndex:3]] integerValue] * 60;
    } else if (match.numberOfRanges > 4 && [match rangeAtIndex:4].location != NSNotFound) {
        minutes = [[masked substringWithRange:[match rangeAtIndex:4]] integerValue];
    }

    result.durationMinutes = minutes;
    [[self class] blankRange:match.range inMasked:masked];

    EventQuickEntrySpan *span = [EventQuickEntrySpan new];
    span.range = match.range;
    span.kind = EventQuickEntrySpanKindDuration;
    span.label = _keywords.durationSpanLabel;
    span.displayValue = [self displayValueForDurationMinutes:minutes];
    return span;
}

- (NSString *)displayValueForDurationMinutes:(NSInteger)minutes
{
    NSString *hourWordPlural = _keywords.hourUnitWords.firstObject ?: @"";
    NSString *hourWordSingular = _keywords.hourUnitWords.count > 1 ? _keywords.hourUnitWords[1] : hourWordPlural;
    NSString *minuteWordPlural = _keywords.minuteUnitWords.firstObject ?: @"";

    NSInteger hours = minutes / 60;
    NSInteger remainder = minutes % 60;

    if (hours == 0) {
        return [NSString stringWithFormat:@"%ld %@", (long)remainder, minuteWordPlural];
    }
    NSString *hoursPart = (hours == 1)
        ? [NSString stringWithFormat:@"1 %@", hourWordSingular]
        : [NSString stringWithFormat:@"%ld %@", (long)hours, hourWordPlural];
    if (remainder == 0) {
        return hoursPart;
    }
    return [NSString stringWithFormat:@"%@ %ld %@", hoursPart, (long)remainder, minuteWordPlural];
}

#pragma mark -
#pragma mark EventQuickEntryLanguagePack — Location

- (nullable EventQuickEntrySpan *)locationSpanInMasked:(NSMutableString *)masked original:(NSString *)original result:(EventQuickEntryResult *)result
{
    NSArray<NSTextCheckingResult *> *prefixMatches = [_locationPrefixRegex matchesInString:masked options:0 range:NSMakeRange(0, masked.length)];
    for (NSTextCheckingResult *prefixMatch in prefixMatches) {
        NSUInteger placeStart = NSMaxRange(prefixMatch.range);
        NSUInteger placeEnd = [self locationPlaceEndInMasked:masked original:original from:placeStart];
        if (placeEnd == NSNotFound) continue;

        // The walked text may end in a leftover dangling preposition, e.g.
        // "Cafe Luna at" when what followed ("noon") has already been
        // blanked by the date detector. That trailing word is folded into
        // the overall (blanked) matchRange below, but trimmed back out of
        // `place` — the value actually assigned to result.location.
        NSUInteger placeCoreEnd = [self placeCoreEndByTrimmingDanglingPrefixFromMasked:masked range:NSMakeRange(placeStart, placeEnd - placeStart)];

        NSString *place = [[masked substringWithRange:NSMakeRange(placeStart, placeCoreEnd - placeStart)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (place.length == 0) continue;

        NSRange matchRange = NSMakeRange(prefixMatch.range.location, placeEnd - prefixMatch.range.location);

        result.location = place;
        [[self class] blankRange:matchRange inMasked:masked];

        EventQuickEntrySpan *span = [EventQuickEntrySpan new];
        span.range = matchRange;
        span.kind = EventQuickEntrySpanKindLocation;
        span.label = _keywords.locationSpanLabel;
        span.displayValue = place;
        return span;
    }
    return nil;
}

// Walks forward from `start`, stopping at a comma (as the old regex did)
// or — the rule a regex can't express — at the first character an earlier
// detector has already blanked, detected by `masked` and `original` no
// longer agreeing at that index. Without this, a location phrase followed
// by an already-blanked span (e.g. "At Cafe Luna for 15 minutes", once
// duration is blanked to spaces) has no way to tell where its own text
// ends and the blanked span's leftover spaces begin — a plain regex
// anchored on "nothing but whitespace to the end of the string" would
// swallow that leftover run right along with the real location text.
// Returns NSNotFound if nothing but whitespace follows `start`.
- (NSUInteger)locationPlaceEndInMasked:(NSString *)masked original:(NSString *)original from:(NSUInteger)start
{
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
    NSUInteger length = masked.length;
    NSUInteger lastNonWhitespace = NSNotFound;
    for (NSUInteger i = start; i < length; i++) {
        unichar maskedChar = [masked characterAtIndex:i];
        if (maskedChar != [original characterAtIndex:i]) break;
        if (maskedChar == ',') break;
        if (![whitespace characterIsMember:maskedChar]) lastNonWhitespace = i;
    }
    return lastNonWhitespace == NSNotFound ? NSNotFound : lastNonWhitespace + 1;
}

// `range` (within `masked`) always ends right where an earlier detector's
// blanked region begins, or at the true end of the string — that's how
// -locationPlaceEndInMasked:original:from: found it. So if `range` itself
// ends in "<real text> PREFIX" (e.g. "Cafe Luna at"), that trailing
// PREFIX has nothing of its own following it — it's a leftover dangling
// preposition from whatever got blanked next door, not part of the place
// name. Returns the end index of the real place text, excluding that
// trailing word (or `range`'s own end, unchanged, if there is none).
- (NSUInteger)placeCoreEndByTrimmingDanglingPrefixFromMasked:(NSString *)masked range:(NSRange)range
{
    NSString *text = [masked substringWithRange:range];
    NSTextCheckingResult *trailingPrefixMatch = [_trailingLocationPrefixRegex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!trailingPrefixMatch) return NSMaxRange(range);
    return range.location + trailingPrefixMatch.range.location;
}

#pragma mark -
#pragma mark EventQuickEntryLanguagePack — Recurrence

- (nullable EventQuickEntrySpan *)recurrenceSpanInMasked:(NSMutableString *)masked result:(EventQuickEntryResult *)result
{
    for (NSInteger i = 0; i < (NSInteger)_recurrenceRegexes.count; i++) {
        NSTextCheckingResult *match = [_recurrenceRegexes[i] firstMatchInString:masked options:0 range:NSMakeRange(0, masked.length)];
        if (match) {
            result.recurrence = (EventQuickEntryRecurrence)_recurrenceValues[i].integerValue;
            [[self class] blankRange:match.range inMasked:masked];

            EventQuickEntrySpan *span = [EventQuickEntrySpan new];
            span.range = match.range;
            span.kind = EventQuickEntrySpanKindRepeat;
            span.label = _keywords.repeatSpanLabel;
            span.displayValue = _recurrenceLabels[i];
            return span;
        }
    }
    return nil;
}

@end
