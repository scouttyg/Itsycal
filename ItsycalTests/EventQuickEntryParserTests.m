//
//  EventQuickEntryParserTests.m
//  ItsycalTests
//

#import <XCTest/XCTest.h>
#import "EventQuickEntryParser.h"

@interface EventQuickEntryParserTests : XCTestCase
@property (nonatomic) EventQuickEntryParser *parser;
@property (nonatomic) NSCalendar *calendar;
@end

@implementation EventQuickEntryParserTests

- (void)setUp
{
    self.parser = [EventQuickEntryParser new];
    self.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
}

- (void)testPlainTextBecomesTitleWithNoOtherFieldsSet
{
    EventQuickEntryResult *result = [self.parser parse:@"Team standup" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Team standup");
    XCTAssertNil(result.date);
    XCTAssertEqual(result.durationMinutes, 0);
    XCTAssertNil(result.location);
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceNone);
    XCTAssertEqual(result.recognizedSpans.count, (NSUInteger)0);
}

- (void)testDetectsDateOnlyPhraseWithoutExplicitTime
{
    EventQuickEntryResult *result = [self.parser parse:@"Dentist tomorrow" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Dentist");
    XCTAssertNotNil(result.date);
    XCTAssertFalse(result.hasExplicitTime);
    XCTAssertEqual(result.recognizedSpans.count, (NSUInteger)1);
}

- (void)testDetectsDateWithExplicitTime
{
    EventQuickEntryResult *result = [self.parser parse:@"Call mom tomorrow at 3pm" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Call mom");
    XCTAssertNotNil(result.date);
    XCTAssertTrue(result.hasExplicitTime);
}

- (void)testDanglingOnPrepositionBeforeDateIsConsumed
{
    EventQuickEntryResult *result = [self.parser parse:@"Meeting with Michele on Friday at 6PM for 10 minutes" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Meeting with Michele");
    XCTAssertNotNil(result.date);
    XCTAssertTrue(result.hasExplicitTime);
    XCTAssertEqual(result.durationMinutes, 10);
}

- (void)testNoDatePhraseLeavesDateNil
{
    EventQuickEntryResult *result = [self.parser parse:@"Buy groceries" calendar:self.calendar];
    XCTAssertNil(result.date);
    XCTAssertFalse(result.hasExplicitTime);
}

- (void)testDetectsDurationInMinutes
{
    EventQuickEntryResult *result = [self.parser parse:@"Meeting for 30 minutes" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Meeting");
    XCTAssertEqual(result.durationMinutes, 30);
}

- (void)testDetectsDurationInHours
{
    EventQuickEntryResult *result = [self.parser parse:@"Workshop for 2 hours" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Workshop");
    XCTAssertEqual(result.durationMinutes, 120);
}

- (void)testDetectsHalfAnHour
{
    EventQuickEntryResult *result = [self.parser parse:@"Sync for half an hour" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Sync");
    XCTAssertEqual(result.durationMinutes, 30);
}

- (void)testDetectsAnHour
{
    EventQuickEntryResult *result = [self.parser parse:@"1:1 for an hour" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"1:1");
    XCTAssertEqual(result.durationMinutes, 60);
}

- (void)testDurationAndDateTogether
{
    EventQuickEntryResult *result = [self.parser parse:@"Meeting with Michele Goci for 30 minutes this Friday" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Meeting with Michele Goci");
    XCTAssertEqual(result.durationMinutes, 30);
    XCTAssertNotNil(result.date);
}

- (void)testDetectsLocationWithAt
{
    EventQuickEntryResult *result = [self.parser parse:@"Lunch at Cafe Luna" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Lunch");
    XCTAssertEqualObjects(result.location, @"Cafe Luna");
}

- (void)testDetectsLocationWithIn
{
    EventQuickEntryResult *result = [self.parser parse:@"Standup in Conference Room B" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Standup");
    XCTAssertEqualObjects(result.location, @"Conference Room B");
}

- (void)testDisambiguatesAtTimeFromAtLocation
{
    EventQuickEntryResult *result = [self.parser parse:@"Lunch with Sam at Cafe Luna at noon" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Lunch with Sam");
    XCTAssertEqualObjects(result.location, @"Cafe Luna");
    XCTAssertNotNil(result.date);
    XCTAssertTrue(result.hasExplicitTime);
}

- (void)testNoLocationPhraseLeavesLocationNil
{
    EventQuickEntryResult *result = [self.parser parse:@"Buy groceries" calendar:self.calendar];
    XCTAssertNil(result.location);
}

- (void)testDetectsEveryDay
{
    EventQuickEntryResult *result = [self.parser parse:@"Standup every day" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Standup");
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceEveryDay);
}

- (void)testDetectsDaily
{
    EventQuickEntryResult *result = [self.parser parse:@"Standup daily" calendar:self.calendar];
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceEveryDay);
}

- (void)testDetectsEveryWeek
{
    EventQuickEntryResult *result = [self.parser parse:@"1:1 every week" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"1:1");
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceEveryWeek);
}

- (void)testDetectsEveryOtherWeek
{
    EventQuickEntryResult *result = [self.parser parse:@"Sprint planning every other week" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Sprint planning");
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceEvery2Weeks);
}

- (void)testDetectsBiweekly
{
    EventQuickEntryResult *result = [self.parser parse:@"Sprint planning biweekly" calendar:self.calendar];
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceEvery2Weeks);
}

- (void)testDetectsEveryMonth
{
    EventQuickEntryResult *result = [self.parser parse:@"Rent due every month" calendar:self.calendar];
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceEveryMonth);
}

- (void)testDetectsEveryYear
{
    EventQuickEntryResult *result = [self.parser parse:@"Anniversary every year" calendar:self.calendar];
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceEveryYear);
}

- (void)testNoRecurrencePhraseLeavesRecurrenceNone
{
    EventQuickEntryResult *result = [self.parser parse:@"Buy groceries" calendar:self.calendar];
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceNone);
}

- (void)testDetectsLocationWithAtSign
{
    EventQuickEntryResult *result = [self.parser parse:@"Standup @ Cafe Luna" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Standup");
    XCTAssertEqualObjects(result.location, @"Cafe Luna");
}

- (void)testAtSignWithoutSpaceIsNotRecognizedAsLocation
{
    EventQuickEntryResult *result = [self.parser parse:@"Standup @Cafe Luna" calendar:self.calendar];
    XCTAssertNil(result.location);
    XCTAssertEqualObjects(result.title, @"Standup @Cafe Luna");
}

- (void)testDateSpanHasLabelAndDisplayValueWithoutExplicitTime
{
    EventQuickEntryResult *result = [self.parser parse:@"Dentist tomorrow" calendar:self.calendar];
    XCTAssertEqual(result.recognizedSpans.count, (NSUInteger)1);
    EventQuickEntrySpan *span = result.recognizedSpans.firstObject;
    XCTAssertEqualObjects(span.label, @"Date");
    XCTAssertFalse([span.displayValue containsString:@":"]); // no time-of-day rendered
}

- (void)testDateSpanHasDisplayValueWithExplicitTime
{
    EventQuickEntryResult *result = [self.parser parse:@"Call mom tomorrow at 3pm" calendar:self.calendar];
    EventQuickEntrySpan *span = result.recognizedSpans.firstObject;
    XCTAssertEqualObjects(span.label, @"Date");
    XCTAssertTrue([span.displayValue containsString:@"at"]);
}

- (void)testDurationSpanDisplayValueMinutesOnly
{
    EventQuickEntryResult *result = [self.parser parse:@"Meeting for 30 minutes" calendar:self.calendar];
    EventQuickEntrySpan *span = result.recognizedSpans.firstObject;
    XCTAssertEqualObjects(span.label, @"Duration");
    XCTAssertEqualObjects(span.displayValue, @"30 minutes");
}

- (void)testDurationSpanDisplayValueHoursOnly
{
    EventQuickEntryResult *result = [self.parser parse:@"Workshop for 2 hours" calendar:self.calendar];
    EventQuickEntrySpan *span = result.recognizedSpans.firstObject;
    XCTAssertEqualObjects(span.displayValue, @"2 hours");
}

- (void)testDurationSpanDisplayValueHoursAndMinutes
{
    EventQuickEntryResult *result = [self.parser parse:@"Meeting for 90 minutes" calendar:self.calendar];
    EventQuickEntrySpan *span = result.recognizedSpans.firstObject;
    XCTAssertEqualObjects(span.displayValue, @"1 hour 30 minutes");
}

- (void)testLocationSpanDisplayValueIsThePlace
{
    EventQuickEntryResult *result = [self.parser parse:@"Lunch at Cafe Luna" calendar:self.calendar];
    EventQuickEntrySpan *span = result.recognizedSpans.firstObject;
    XCTAssertEqualObjects(span.label, @"Location");
    XCTAssertEqualObjects(span.displayValue, @"Cafe Luna");
}

- (void)testRecurrenceSpanDisplayValueMatchesRepPopupTitle
{
    EventQuickEntryResult *result = [self.parser parse:@"Standup every day" calendar:self.calendar];
    EventQuickEntrySpan *span = result.recognizedSpans.firstObject;
    XCTAssertEqualObjects(span.label, @"Repeat");
    XCTAssertEqualObjects(span.displayValue, @"Every Day");
}

- (void)testUsesImpliedDurationFromTimeRange
{
    EventQuickEntryResult *result = [self.parser parse:@"Meeting 3-4pm Friday" calendar:self.calendar];
    XCTAssertEqual(result.durationMinutes, 60);
    XCTAssertTrue(result.hasExplicitTime);
}

- (void)testExplicitForPhraseWinsOverImpliedDuration
{
    EventQuickEntryResult *result = [self.parser parse:@"Meeting 3-4pm for 30 minutes" calendar:self.calendar];
    XCTAssertEqual(result.durationMinutes, 30);
}

- (void)testHasExplicitTimeForMorning
{
    EventQuickEntryResult *result = [self.parser parse:@"Coffee tomorrow morning" calendar:self.calendar];
    XCTAssertTrue(result.hasExplicitTime);
    NSInteger hour = [self.calendar component:NSCalendarUnitHour fromDate:result.date];
    XCTAssertEqual(hour, 9);
}

- (void)testHasExplicitTimeForAfternoon
{
    EventQuickEntryResult *result = [self.parser parse:@"Coffee tomorrow afternoon" calendar:self.calendar];
    XCTAssertTrue(result.hasExplicitTime);
    NSInteger hour = [self.calendar component:NSCalendarUnitHour fromDate:result.date];
    XCTAssertEqual(hour, 15);
}

- (void)testHasExplicitTimeForEvening
{
    EventQuickEntryResult *result = [self.parser parse:@"Call tomorrow evening" calendar:self.calendar];
    XCTAssertTrue(result.hasExplicitTime);
    NSInteger hour = [self.calendar component:NSCalendarUnitHour fromDate:result.date];
    XCTAssertEqual(hour, 18);
}

- (void)testRestoresLeadingMealWordSwallowedByDateMatch
{
    EventQuickEntryResult *result = [self.parser parse:@"Lunch tomorrow afternoon" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Lunch");
    XCTAssertNotNil(result.date);
}

#pragma mark - Language pack registry

- (void)testRegistryReturnsEnglishPackForEnglishCode
{
    id<EventQuickEntryLanguagePack> pack = [EventQuickEntryLanguagePackRegistry packForLanguageCode:@"en"];
    XCTAssertTrue([pack isKindOfClass:[EventQuickEntryEnglishLanguagePack class]]);
}

- (void)testRegistryReturnsSpanishPackForSpanishCode
{
    id<EventQuickEntryLanguagePack> pack = [EventQuickEntryLanguagePackRegistry packForLanguageCode:@"es"];
    XCTAssertTrue([pack isKindOfClass:[EventQuickEntrySpanishLanguagePack class]]);
}

- (void)testRegistryReturnsNilForUnsupportedCode
{
    id<EventQuickEntryLanguagePack> pack = [EventQuickEntryLanguagePackRegistry packForLanguageCode:@"de"];
    XCTAssertNil(pack);
}

#pragma mark - Spanish language pack

- (void)testSpanishDetectsDateWithoutSwallowingTitle
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Reunión mañana" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Reunión");
    XCTAssertNotNil(result.date);
}

- (void)testSpanishStripsDanglingElBeforeDate
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Reunión el próximo lunes" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Reunión");
    XCTAssertNotNil(result.date);
}

- (void)testSpanishStripsDanglingEstaBeforeDate
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Cena esta noche" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Cena");
    XCTAssertNotNil(result.date);
    XCTAssertTrue(result.hasExplicitTime);
}

- (void)testSpanishDetectsExplicitTimeWithAmPm
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Almuerzo mañana a las 3pm" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Almuerzo");
    XCTAssertTrue(result.hasExplicitTime);
}

- (void)testSpanishDetectsDuration
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Reunión durante 30 minutos" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Reunión");
    XCTAssertEqual(result.durationMinutes, 30);
}

- (void)testSpanishDetectsHalfHourIdiom
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Reunión durante media hora" calendar:self.calendar];
    XCTAssertEqual(result.durationMinutes, 30);
}

- (void)testSpanishDetectsLocation
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Almuerzo en Cafe Luna" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Almuerzo");
    XCTAssertEqualObjects(result.location, @"Cafe Luna");
}

- (void)testSpanishDetectsRecurrenceEveryDay
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Reunión todos los días" calendar:self.calendar];
    XCTAssertEqualObjects(result.title, @"Reunión");
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceEveryDay);
}

- (void)testSpanishRecurrenceSpanDisplayValueMatchesExistingTranslation
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Reunión todos los días" calendar:self.calendar];
    XCTAssertEqual(result.recognizedSpans.count, (NSUInteger)1);
    EventQuickEntrySpan *span = result.recognizedSpans.firstObject;
    XCTAssertEqualObjects(span.label, @"Repetir");
    XCTAssertEqualObjects(span.displayValue, @"Todos los días");
}

- (void)testSpanishNoRecurrencePhraseLeavesRecurrenceNone
{
    EventQuickEntryParser *parser = [[EventQuickEntryParser alloc] initWithLanguagePack:[EventQuickEntrySpanishLanguagePack new]];
    EventQuickEntryResult *result = [parser parse:@"Comprar víveres" calendar:self.calendar];
    XCTAssertEqual(result.recurrence, EventQuickEntryRecurrenceNone);
    XCTAssertNil(result.location);
}

@end
