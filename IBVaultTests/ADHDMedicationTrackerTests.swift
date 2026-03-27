import Testing
import Foundation

@testable import IBVault

@Suite("ADHD Medication Tracker Tests")
struct ADHDMedicationTrackerTests {
    
    @Test("ADHD medication type should have correct display names")
    func testMedicationTypeDisplayNames() {
        #expect(ADHDMedicationType.methylphenidateIR.displayName == "Methylphenidate IR")
        #expect(ADHDMedicationType.methylphenidateER.displayName == "Methylphenidate ER")
        #expect(ADHDMedicationType.amphetamineIR.displayName == "Amphetamine IR")
        #expect(ADHDMedicationType.lisdexamfetamine.displayName == "Lisdexamfetamine")
        #expect(ADHDMedicationType.none.displayName == "None")
    }
    
    @Test("Typical doses should be defined for each medication")
    func testTypicalDoses() {
        #expect(!ADHDMedicationType.methylphenidateIR.typicalDosesMg.isEmpty)
        #expect(!ADHDMedicationType.amphetamineIR.typicalDosesMg.isEmpty)
        #expect(!ADHDMedicationType.lisdexamfetamine.typicalDosesMg.isEmpty)
        #expect(ADHDMedicationType.none.typicalDosesMg.isEmpty)
    }
    
    @Test("Stimulant medications should be identified correctly")
    func testStimulantIdentification() {
        #expect(ADHDMedicationType.methylphenidateIR.isStimulant == true)
        #expect(ADHDMedicationType.amphetamineIR.isStimulant == true)
        #expect(ADHDMedicationType.lisdexamfetamine.isStimulant == true)
        #expect(ADHDMedicationType.atomoxetine.isStimulant == false)
        #expect(ADHDMedicationType.guanfacine.isStimulant == false)
        #expect(ADHDMedicationType.none.isStimulant == false)
    }
    
    @Test("Duration hours should be defined for each medication")
    func testDurationHours() {
        #expect(ADHDMedicationType.methylphenidateIR.durationHours == 4.0)
        #expect(ADHDMedicationType.methylphenidateER.durationHours == 12.0)
        #expect(ADHDMedicationType.amphetamineIR.durationHours == 6.0)
        #expect(ADHDMedicationType.amphetamineXR.durationHours == 12.0)
        #expect(ADHDMedicationType.lisdexamfetamine.durationHours == 14.0)
    }
    
    @Test("Peak hours should be positive for non-none medications")
    func testPeakHours() {
        #expect(ADHDMedicationType.methylphenidateIR.peakHoursAfterDose > 0)
        #expect(ADHDMedicationType.lisdexamfetamine.peakHoursAfterDose > 0)
        #expect(ADHDMedicationType.none.peakHoursAfterDose == 0)
    }
    
    @Test("Disabled medication should return zero plasma level")
    func testDisabledMedicationPlasmaLevel() {
        var settings = ADHDMedicationSettings.default
        settings.isEnabled = false
        settings.medicationType = .methylphenidateIR
        
        let level = ADHDMedicationTracker.estimatePlasmaLevel(at: Date(), settings: settings)
        
        #expect(level == 0)
    }
    
    @Test("None medication type should return zero plasma level")
    func testNoneMedicationPlasmaLevel() {
        var settings = ADHDMedicationSettings.default
        settings.isEnabled = true
        settings.medicationType = .none
        
        let level = ADHDMedicationTracker.estimatePlasmaLevel(at: Date(), settings: settings)
        
        #expect(level == 0)
    }
    
    @Test("Enabled medication should return positive plasma level during active window")
    func testEnabledMedicationPlasmaLevel() {
        var settings = ADHDMedicationSettings.default
        settings.isEnabled = true
        settings.medicationType = .methylphenidateIR
        settings.doseMg = 10
        settings.dailyDoses = 3
        settings.firstDoseHour = 9
        settings.firstDoseMinute = 0
        settings.doseIntervalMinutes = 270
        
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = 11
        components.minute = 0
        let testDate = calendar.date(from: components) ?? Date()
        
        let level = ADHDMedicationTracker.estimatePlasmaLevel(at: testDate, settings: settings)
        
        #expect(level > 0)
    }
    
    @Test("Current focus status for disabled medication should be not active")
    func testDisabledFocusStatus() {
        var settings = ADHDMedicationSettings.default
        settings.isEnabled = false
        
        let status = ADHDMedicationTracker.currentFocusStatus(at: Date(), settings: settings)
        
        #expect(status.level == 0)
        #expect(status.status == "Not Active")
        #expect(status.colorName == "gray")
    }
    
    @Test("Focus windows should be empty for disabled medication")
    func testDisabledFocusWindows() {
        var settings = ADHDMedicationSettings.default
        settings.isEnabled = false
        
        let windows = ADHDMedicationTracker.focusWindows(settings: settings)
        
        #expect(windows.isEmpty)
    }
    
    @Test("Focus windows should be generated for enabled medication")
    func testEnabledFocusWindows() {
        var settings = ADHDMedicationSettings.default
        settings.isEnabled = true
        settings.medicationType = .methylphenidateIR
        settings.doseMg = 10
        settings.dailyDoses = 3
        settings.firstDoseHour = 9
        settings.firstDoseMinute = 0
        settings.doseIntervalMinutes = 270
        
        let windows = ADHDMedicationTracker.focusWindows(settings: settings)
        
        #expect(windows.count == 3)
    }
    
    @Test("Settings should save and load from defaults")
    func testSettingsPersistence() {
        var original = ADHDMedicationSettings.default
        original.medicationType = .lisdexamfetamine
        original.doseMg = 50
        original.dailyDoses = 1
        original.firstDoseHour = 8
        original.firstDoseMinute = 30
        original.isEnabled = true
        
        original.saveToDefaults()
        
        let loaded = ADHDMedicationSettings.loadFromDefaults()
        
        #expect(loaded.medicationType == .lisdexamfetamine)
        #expect(loaded.doseMg == 50)
        #expect(loaded.dailyDoses == 1)
        #expect(loaded.firstDoseHour == 8)
        #expect(loaded.firstDoseMinute == 30)
        #expect(loaded.isEnabled == true)
        
        ADHDMedicationSettings.clearFromDefaults()
    }
    
    @Test("Default settings should have none medication type")
    func testDefaultSettings() {
        let settings = ADHDMedicationSettings.default
        
        #expect(settings.medicationType == .none)
        #expect(settings.isEnabled == false)
    }
}