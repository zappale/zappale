import XCTest

@testable import ZappaleCore
@testable import zappale

final class CalcEngineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.apply(.zhHans)
    }

    // MARK: 基本算术

    func testSimpleArithmetic() {
        XCTAssertEqual(CalcEngine.evaluate("1+1")?.display, "= 2")
        XCTAssertEqual(CalcEngine.evaluate("2*3+4")?.display, "= 10")
        XCTAssertEqual(CalcEngine.evaluate("2+3*4")?.display, "= 14")
        XCTAssertEqual(CalcEngine.evaluate("(2+3)*4")?.display, "= 20")
        XCTAssertEqual(CalcEngine.evaluate("10/4")?.display, "= 2.5")
        XCTAssertEqual(CalcEngine.evaluate("2^10")?.display, "= 1,024")
        XCTAssertEqual(CalcEngine.evaluate("-5+3")?.display, "= -2")
    }

    func testImplicitMultiplication() {
        XCTAssertEqual(CalcEngine.evaluate("2pi")?.display, "= 6.28319")
        XCTAssertEqual(CalcEngine.evaluate("2(3+4)")?.display, "= 14")
        XCTAssertEqual(CalcEngine.evaluate("(1+2)(3+4)")?.display, "= 21")
    }

    func testFunctionsAndConstants() {
        XCTAssertEqual(CalcEngine.evaluate("sqrt(16)")?.display, "= 4")
        XCTAssertEqual(CalcEngine.evaluate("sqrt 16")?.display, "= 4")
        XCTAssertEqual(CalcEngine.evaluate("max(3, 7)")?.display, "= 7")
        XCTAssertEqual(CalcEngine.evaluate("min(3, 7)")?.display, "= 3")
        XCTAssertEqual(CalcEngine.evaluate("log(100)")?.display, "= 2")
        XCTAssertEqual(CalcEngine.evaluate("sin(0)")?.display, "= 0")
        XCTAssertEqual(CalcEngine.evaluate("sin(30deg)")?.display, "= 0.5")
        XCTAssertEqual(CalcEngine.evaluate("pow(2, 8)")?.display, "= 256")
    }

    func testPercent() {
        XCTAssertEqual(CalcEngine.evaluate("200+10%")?.display, "= 220")
        XCTAssertEqual(CalcEngine.evaluate("200-10%")?.display, "= 180")
        XCTAssertEqual(CalcEngine.evaluate("50*10%")?.display, "= 5")
        XCTAssertEqual(CalcEngine.evaluate("10%")?.display, "= 0.1")
        XCTAssertEqual(CalcEngine.evaluate("100+(2+3)%")?.display, "= 105")
    }

    // MARK: 单位换算

    func testUnitConversion() {
        XCTAssertEqual(CalcEngine.evaluate("10km to mi")?.display, "= 6.21371 mi")
        XCTAssertEqual(CalcEngine.evaluate("100kg in lb")?.display, nil) // in 是英寸，不是换算词
        XCTAssertEqual(CalcEngine.evaluate("100kg to lb")?.display, "= 220.462 lb")
        XCTAssertEqual(CalcEngine.evaluate("m to ft")?.display, "= 3.28084 ft")
        XCTAssertEqual(CalcEngine.evaluate("100c to f")?.display, "= 212 f")
        XCTAssertEqual(CalcEngine.evaluate("1gb to mb")?.display, "= 1,000 mb")
        XCTAssertEqual(CalcEngine.evaluate("1mib to kib")?.display, "= 1,024 kib")
        XCTAssertEqual(CalcEngine.evaluate("90deg to rad")?.display, "= 1.5708 rad")
        XCTAssertEqual(CalcEngine.evaluate("1hr to min")?.display, "= 60 min")
        XCTAssertEqual(CalcEngine.evaluate("1 m to ft")?.display, "= 3.28084 ft")
    }

    func testTypedQuantityArithmetic() {
        XCTAssertEqual(CalcEngine.evaluate("10kg+500g")?.display, "= 10.5 kg")
        XCTAssertEqual(CalcEngine.evaluate("10 kg + 500 g")?.display, "= 10.5 kg")
        XCTAssertEqual(CalcEngine.evaluate("5m*4m")?.display, "= 20 m2")
        XCTAssertEqual(CalcEngine.evaluate("100km/2h")?.display, "= 50 km/h")
        XCTAssertEqual(CalcEngine.evaluate("1/20ms to hz")?.display, "= 50 hz")
        XCTAssertEqual(CalcEngine.evaluate("2m/2m")?.display, "= 1")
    }

    func testDerivedUnitDisplay() {
        XCTAssertEqual(CalcEngine.evaluate("1hr+30min")?.display, "= 1.5 hr")
    }

    // MARK: 进制

    func testRadix() {
        XCTAssertEqual(CalcEngine.evaluate("0xff")?.display, "= 255")
        XCTAssertEqual(CalcEngine.evaluate("255 to hex")?.display, "= 0xff")
        XCTAssertEqual(CalcEngine.evaluate("0xff to bin")?.display, "= 0b11111111")
        XCTAssertEqual(CalcEngine.evaluate("8 to oct")?.display, "= 0o10")
        XCTAssertEqual(CalcEngine.evaluate("2m/2m to hex")?.display, "= 0x1")
    }

    // MARK: 不该触发计算卡的输入

    func testNonCalculationsReturnNil() {
        XCTAssertNil(CalcEngine.evaluate("safari"))
        XCTAssertNil(CalcEngine.evaluate("微信"))
        XCTAssertNil(CalcEngine.evaluate("hello world"))
        XCTAssertNil(CalcEngine.evaluate(""))
        XCTAssertNil(CalcEngine.evaluate("5 cats"))
        XCTAssertNil(CalcEngine.evaluate("lock to door"))
    }

    func testTrailingOperatorStillEvaluates() {
        XCTAssertEqual(CalcEngine.evaluate("5*3+")?.display, "= 15")
    }

    func testFormatter() {
        XCTAssertEqual(CalcFormatter.display(0), "0")
        XCTAssertEqual(CalcFormatter.display(1234567), "1,234,567")
        XCTAssertEqual(CalcFormatter.display(-1234567.5), "-1,234,567.5")
        XCTAssertEqual(CalcFormatter.display(0.1 + 0.2), "0.3")
        // 复制精度更高
        XCTAssertEqual(CalcFormatter.copyText(10.0 / 3), "3.33333333333")
        XCTAssertEqual(CalcFormatter.display(1e20), "1e20")
        XCTAssertNil(CalcFormatter.display(.infinity))
    }
}

// MARK: - M4 增强：自然语言 + 新单位

extension CalcEngineTests {
    func testPercentOf() {
        XCTAssertEqual(CalcEngine.evaluate("20% of 50")?.display, "= 10")
        XCTAssertEqual(CalcEngine.evaluate("12.5% of 200")?.display, "= 25")
    }

    func testNewUnitFamilies() {
        XCTAssertEqual(CalcEngine.evaluate("1bar to psi")?.display, "= 14.5038 psi")
        XCTAssertEqual(CalcEngine.evaluate("100kpa to bar")?.display, "= 1 bar")
        XCTAssertEqual(CalcEngine.evaluate("1hp to kw")?.display, "= 0.7457 kw")
        XCTAssertEqual(CalcEngine.evaluate("100mbps to mb/s")?.display, "= 12.5 mb/s")
        XCTAssertEqual(CalcEngine.evaluate("1gb/s to mbps")?.display, "= 8,000 mbps")
    }

    func testCountdownDays() {
        let now = dateUTC(2026, 9, 18, 12)
        // 2026-12-25 距 9-18 = 97 天（当日零点起算）
        let result = CalcEngine.evaluate("days till 2026-12-25", now: now)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.display.hasSuffix("天"))
    }

    func testCountdownHoursToTime() {
        let now = dateUTC(2026, 9, 18, 9)
        let result = CalcEngine.evaluate("hrs till 18:00", now: now)
        XCTAssertNotNil(result)
    }

    func testDateArithmetic() {
        let now = dateUTC(2026, 9, 18, 12)
        XCTAssertEqual(CalcEngine.evaluate("today + 3 days", now: now)?.display, "= 2026-09-21")
        XCTAssertEqual(CalcEngine.evaluate("today + 2 weeks", now: now)?.display, "= 2026-10-02")
        XCTAssertEqual(CalcEngine.evaluate("today - 1 day", now: now)?.display, "= 2026-09-17")
        XCTAssertNil(CalcEngine.evaluate("today plus lunch", now: now))
    }

    func testTimeInCity() {
        let now = dateUTC(2026, 9, 18, 4) // UTC 04:00 = 东京 13:00
        let result = CalcEngine.evaluate("time in tokyo", now: now)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.display.contains("东京 Tokyo 09-18 13:00"))
        let zh = CalcEngine.evaluate("伦敦时间", now: now)
        XCTAssertNotNil(zh)
        XCTAssertTrue(zh!.display.contains("伦敦 London"))
    }

    private func dateUTC(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        var components = DateComponents()
        components.year = y; components.month = m; components.day = d; components.hour = h
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }
}
