//
//  EventQuickEntryParser.m
//  Itsycal
//

#import "EventQuickEntryParser.h"

@implementation EventQuickEntrySpan
@end

@implementation EventQuickEntryResult

- (instancetype)init
{
    self = [super init];
    if (self) {
        _title = @"";
        _date = nil;
        _hasExplicitTime = NO;
        _durationMinutes = 0;
        _location = nil;
        _recurrence = EventQuickEntryRecurrenceNone;
        _recognizedSpans = @[];
    }
    return self;
}

@end

@implementation EventQuickEntryParser

- (EventQuickEntryResult *)parse:(NSString *)text calendar:(NSCalendar *)calendar
{
    EventQuickEntryResult *result = [EventQuickEntryResult new];
    NSString *original = text ?: @"";
    NSMutableString *masked = [original mutableCopy];
    NSMutableArray<EventQuickEntrySpan *> *recognizedSpans = [NSMutableArray new];

    EventQuickEntrySpan *dateSpan = [self applyDateDetectionToMasked:masked original:original result:result calendar:calendar];
    if (dateSpan) [recognizedSpans addObject:dateSpan];

    EventQuickEntrySpan *durationSpan = [self applyDurationDetectionToMasked:masked result:result];
    if (durationSpan) [recognizedSpans addObject:durationSpan];

    EventQuickEntrySpan *locationSpan = [self applyLocationDetectionToMasked:masked result:result];
    if (locationSpan) [recognizedSpans addObject:locationSpan];

    EventQuickEntrySpan *recurrenceSpan = [self applyRecurrenceDetectionToMasked:masked result:result];
    if (recurrenceSpan) [recognizedSpans addObject:recurrenceSpan];

    result.title = [self titleFromMaskedText:masked];
    result.recognizedSpans = recognizedSpans;

    return result;
}

#pragma mark - Date/time

- (EventQuickEntrySpan *)applyDateDetectionToMasked:(NSMutableString *)masked
                                            original:(NSString *)original
                                              result:(EventQuickEntryResult *)result
                                            calendar:(NSCalendar *)calendar
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
    // "3-4pm". Set it here so an explicit "for X minutes" phrase (handled
    // later in the pipeline) can still unconditionally override it.
    if (match.duration > 0) {
        result.durationMinutes = (NSInteger)round(match.duration / 60.0);
    }

    NSRange rangeToBlank = [self rangeToBlankForDateMatch:match inOriginal:original];
    [self blankRange:rangeToBlank inMasked:masked];

    EventQuickEntrySpan *span = [EventQuickEntrySpan new];
    span.range = rangeToBlank;
    span.kind = EventQuickEntrySpanKindDate;
    span.label = @"Date";
    span.displayValue = [self displayValueForDate:result.date hasExplicitTime:result.hasExplicitTime calendar:calendar];
    return span;
}

// NSDataDetector's own match range doesn't always line up with what should
// actually be blanked out of the title: it sometimes folds a leading meal
// word ("Lunch", "Dinner") into its own match as a time-of-day reference,
// and it never includes a dangling leading preposition ("on Friday") that
// precedes the match. This adjusts for both before anything gets blanked.
- (NSRange)rangeToBlankForDateMatch:(NSTextCheckingResult *)match inOriginal:(NSString *)original
{
    NSRange coreRange = match.range;
    static NSRegularExpression *mealWordRegex;
    static dispatch_once_t mealWordOnceToken;
    dispatch_once(&mealWordOnceToken, ^{
        mealWordRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)^\\b(?:lunch|breakfast|dinner|brunch)\\b\\s*"
                                                                    options:0
                                                                      error:nil];
    });
    NSTextCheckingResult *mealMatch = [mealWordRegex firstMatchInString:original options:0 range:match.range];
    if (mealMatch) {
        NSUInteger newLocation = NSMaxRange(mealMatch.range);
        coreRange = NSMakeRange(newLocation, NSMaxRange(match.range) - newLocation);
    }

    NSRange rangeToBlank = coreRange;

    static NSRegularExpression *danglingOnRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        danglingOnRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\bon\\s+$"
                                                                      options:0
                                                                        error:nil];
    });

    NSTextCheckingResult *onMatch = [danglingOnRegex firstMatchInString:original
                                                                  options:0
                                                                    range:NSMakeRange(0, coreRange.location)];
    if (onMatch) {
        rangeToBlank = NSMakeRange(onMatch.range.location, NSMaxRange(coreRange) - onMatch.range.location);
    }

    return rangeToBlank;
}

- (NSString *)displayValueForDate:(NSDate *)date hasExplicitTime:(BOOL)hasExplicitTime calendar:(NSCalendar *)calendar
{
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    dateFormatter.calendar = calendar;
    [dateFormatter setLocalizedDateFormatFromTemplate:@"EEEEMMMMd"];
    NSString *dateString = [dateFormatter stringFromDate:date];

    if (!hasExplicitTime) return dateString;

    NSDateFormatter *timeFormatter = [NSDateFormatter new];
    timeFormatter.calendar = calendar;
    timeFormatter.dateStyle = NSDateFormatterNoStyle;
    timeFormatter.timeStyle = NSDateFormatterShortStyle;
    NSString *timeString = [timeFormatter stringFromDate:date];

    return [NSString stringWithFormat:@"%@ at %@", dateString, timeString];
}

- (BOOL)textContainsExplicitTime:(NSString *)text
{
    static NSRegularExpression *timeRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        timeRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\b\\d{1,2}(:\\d{2})?\\s*(am|pm|a\\.m\\.|p\\.m\\.)\\b|\\b\\d{1,2}:\\d{2}\\b|\\bnoon\\b|\\bmidnight\\b|\\bmorning\\b|\\bafternoon\\b|\\bevening\\b"
                                                                options:0
                                                                  error:nil];
    });
    return [timeRegex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

#pragma mark - Duration

- (EventQuickEntrySpan *)applyDurationDetectionToMasked:(NSMutableString *)masked result:(EventQuickEntryResult *)result
{
    static NSRegularExpression *durationRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        durationRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)\\bfor\\s+half\\s+an\\s+hour\\b|\\bfor\\s+(?:a|an)\\s+hour\\b|\\bfor\\s+(\\d+)\\s*(?:hours|hour|hrs|hr)\\b|\\bfor\\s+(\\d+)\\s*(?:minutes|minute|mins|min)\\b"
                                                                     options:0
                                                                       error:nil];
    });

    NSTextCheckingResult *match = [durationRegex firstMatchInString:masked options:0 range:NSMakeRange(0, masked.length)];
    if (!match) return nil;

    NSString *matchedText = [masked substringWithRange:match.range];
    NSString *lowerMatched = matchedText.lowercaseString;
    NSInteger minutes = 0;
    if ([lowerMatched containsString:@"half"]) {
        minutes = 30;
    } else if ([lowerMatched hasSuffix:@"hour"]) {
        minutes = 60; // "for a hour" / "for an hour"
    } else if (match.numberOfRanges > 1 && [match rangeAtIndex:1].location != NSNotFound) {
        minutes = [[masked substringWithRange:[match rangeAtIndex:1]] integerValue] * 60;
    } else if (match.numberOfRanges > 2 && [match rangeAtIndex:2].location != NSNotFound) {
        minutes = [[masked substringWithRange:[match rangeAtIndex:2]] integerValue];
    }

    result.durationMinutes = minutes;
    [self blankRange:match.range inMasked:masked];

    EventQuickEntrySpan *span = [EventQuickEntrySpan new];
    span.range = match.range;
    span.kind = EventQuickEntrySpanKindDuration;
    span.label = @"Duration";
    span.displayValue = [self displayValueForDurationMinutes:minutes];
    return span;
}

- (NSString *)displayValueForDurationMinutes:(NSInteger)minutes
{
    NSInteger hours = minutes / 60;
    NSInteger remainder = minutes % 60;

    if (hours == 0) {
        return [NSString stringWithFormat:@"%ld minutes", (long)remainder];
    }
    NSString *hoursPart = (hours == 1) ? @"1 hour" : [NSString stringWithFormat:@"%ld hours", (long)hours];
    if (remainder == 0) {
        return hoursPart;
    }
    return [NSString stringWithFormat:@"%@ %ld minutes", hoursPart, (long)remainder];
}

#pragma mark - Location

- (EventQuickEntrySpan *)applyLocationDetectionToMasked:(NSMutableString *)masked result:(EventQuickEntryResult *)result
{
    static NSRegularExpression *locationRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        locationRegex = [NSRegularExpression regularExpressionWithPattern:@"(?i)(?:\\b(?:at|in)|@)\\s+([A-Za-z0-9][^,]*?)(?:\\s+(?:at|in|@))?\\s*$"
                                                                   options:0
                                                                     error:nil];
    });

    NSTextCheckingResult *match = [locationRegex firstMatchInString:masked options:0 range:NSMakeRange(0, masked.length)];
    if (!match) return nil;

    NSRange placeRange = [match rangeAtIndex:1];
    if (placeRange.location == NSNotFound) return nil;

    NSString *place = [[masked substringWithRange:placeRange] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (place.length == 0) return nil;

    result.location = place;
    [self blankRange:match.range inMasked:masked];

    EventQuickEntrySpan *span = [EventQuickEntrySpan new];
    span.range = match.range;
    span.kind = EventQuickEntrySpanKindLocation;
    span.label = @"Location";
    span.displayValue = place;
    return span;
}

#pragma mark - Recurrence

- (EventQuickEntrySpan *)applyRecurrenceDetectionToMasked:(NSMutableString *)masked result:(EventQuickEntryResult *)result
{
    static NSArray<NSRegularExpression *> *recurrenceRegexes;
    static NSArray<NSNumber *> *recurrenceValues;
    static NSArray<NSString *> *recurrenceLabels;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // "every other week"/"biweekly" is checked before the plain
        // "every week" pattern so it isn't shadowed by it.
        NSArray<NSString *> *patterns = @[
            @"(?i)\\bevery\\s+other\\s+week\\b|\\bbiweekly\\b",
            @"(?i)\\bevery\\s+day\\b|\\bdaily\\b",
            @"(?i)\\bevery\\s+week\\b|\\bweekly\\b",
            @"(?i)\\bevery\\s+month\\b|\\bmonthly\\b",
            @"(?i)\\bevery\\s+year\\b|\\byearly\\b|\\bannually\\b",
        ];
        NSMutableArray<NSRegularExpression *> *regexes = [NSMutableArray new];
        for (NSString *pattern in patterns) {
            [regexes addObject:[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil]];
        }
        recurrenceRegexes = regexes;
        recurrenceValues = @[
            @(EventQuickEntryRecurrenceEvery2Weeks),
            @(EventQuickEntryRecurrenceEveryDay),
            @(EventQuickEntryRecurrenceEveryWeek),
            @(EventQuickEntryRecurrenceEveryMonth),
            @(EventQuickEntryRecurrenceEveryYear),
        ];
        // Index-parallel with recurrenceValues; must match EventViewController's
        // _repPopup item titles exactly (EventViewController.m).
        recurrenceLabels = @[
            @"Every 2 Weeks",
            @"Every Day",
            @"Every Week",
            @"Every Month",
            @"Every Year",
        ];
    });

    for (NSInteger i = 0; i < (NSInteger)recurrenceRegexes.count; i++) {
        NSTextCheckingResult *match = [recurrenceRegexes[i] firstMatchInString:masked options:0 range:NSMakeRange(0, masked.length)];
        if (match) {
            result.recurrence = (EventQuickEntryRecurrence)recurrenceValues[i].integerValue;
            [self blankRange:match.range inMasked:masked];

            EventQuickEntrySpan *span = [EventQuickEntrySpan new];
            span.range = match.range;
            span.kind = EventQuickEntrySpanKindRepeat;
            span.label = @"Repeat";
            span.displayValue = recurrenceLabels[i];
            return span;
        }
    }
    return nil;
}

#pragma mark - Title / helpers

- (NSString *)titleFromMaskedText:(NSString *)masked
{
    NSString *collapsed = [self collapseWhitespace:masked];
    return [collapsed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)collapseWhitespace:(NSString *)text
{
    static NSRegularExpression *whitespaceRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        whitespaceRegex = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:nil];
    });
    return [whitespaceRegex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@" "];
}

- (void)blankRange:(NSRange)range inMasked:(NSMutableString *)masked
{
    NSString *blank = [@"" stringByPaddingToLength:range.length withString:@" " startingAtIndex:0];
    [masked replaceCharactersInRange:range withString:blank];
}

@end
