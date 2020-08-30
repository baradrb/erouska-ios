//
//  CurrentDataVM.swift
//  BT-Tracking
//
//  Created by Naim Ashhab on 25/08/2020.
//  Copyright © 2020 Covid19CZ. All rights reserved.
//

import UIKit
import FirebaseFunctions
import RealmSwift
import RxSwift

final class CurrentDataVM {

    let tabTitle = "data_list_title"
    let tabIcon = UIImage(named: "MyData")

    let measuresURL = URL(string: RemoteValues.currentMeasuresUrl)!

    var sections: [Section] = [] {
        didSet {
            needToUpdateView.onNext(())
        }
    }
    var footer: String? {
        didSet {
            needToUpdateView.onNext(())
        }
    }
    let needToUpdateView: BehaviorSubject<Void>
    let obervableErrors: BehaviorSubject<Error?>

    private var currentData: CurrentDataRealm?

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.groupingSeparator = " "
        formatter.numberStyle = .decimal
        return formatter
    }()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd. MM. yyyy"
        return formatter
    }()

    init() {
        needToUpdateView = BehaviorSubject<Void>(value: ())
        obervableErrors = BehaviorSubject<Error?>(value: nil)

        let realm = try! Realm()
        currentData = realm.objects(CurrentDataRealm.self).last
        sections = sections(from: currentData)

        if currentData == nil {
            let currentData = CurrentDataRealm()
            try? realm.write {
                realm.add(currentData)
            }
            self.currentData = currentData
        }

        updateFooter()
    }

    func fetchCurrentDataIfNeeded() {
        if let lastFetchedDate = AppSettings.currentDataLastFetchDate {
            var components = DateComponents()
            components.hour = 3
            if Calendar.current.date(byAdding: components, to: lastFetchedDate)! > Date() { return }
        }

        AppDelegate.dependency.functions.httpsCallable("GetCovidData").call([:]) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result?.data as? [String: Any] {
                let realm = try! Realm()
                try! realm.write {
                    if let value = result["testsTotal"] as? Int { self.currentData?.testsTotal = value }
                    if let value = result["testsIncrease"] as? Int { self.currentData?.testsIncrease = value }
                    if let value = result["confirmedCasesTotal"] as? Int { self.currentData?.confirmedCasesTotal = value }
                    if let value = result["confirmedCasesIncrease"] as? Int { self.currentData?.confirmedCasesIncrease = value }
                    if let value = result["activeCasesTotal"] as? Int { self.currentData?.activeCasesTotal = value }
                    if let value = result["activeCasesIncrease"] as? Int { self.currentData?.activeCasesIncrease = value }
                    if let value = result["curedTotal"] as? Int { self.currentData?.curedTotal = value }
                    if let value = result["curedIncrease"] as? Int { self.currentData?.curedIncrease = value }
                    if let value = result["deceasedTotal"] as? Int { self.currentData?.deceasedTotal = value }
                    if let value = result["deceasedIncrease"] as? Int { self.currentData?.deceasedIncrease = value }
                    if let value = result["currentlyHospitalizedTotal"] as? Int { self.currentData?.currentlyHospitalizedTotal = value }
                    if let value = result["currentlyHospitalizedIncrease"] as? Int { self.currentData?.currentlyHospitalizedIncrease = value }

                    self.sections = self.sections(from: self.currentData)
                    AppSettings.currentDataLastFetchDate = Date()
                    self.updateFooter()
                }
            } else if let error = error {
                if AppSettings.currentDataLastFetchDate == nil {
                    self.obervableErrors.onNext(error)
                }
            }
        }
    }

    private func updateFooter() {
        if let lastFetchedDate = AppSettings.currentDataLastFetchDate {
            footer = String(format: Localizable("current_data_footer"), dateFormatter.string(from: lastFetchedDate))
        }
    }

    private func sections(from currentData: CurrentDataRealm?) -> [Section] {
        guard let data = currentData else { return [] }
        return [
            Section(header: nil, selectableItems: true, items: [
                Item(iconName: "CurrentData/Measures", title: Localizable("current_data_measures"), subtitle: nil),
            ]),
            Section(header: Localizable("current_data_item_header"), selectableItems: false, items: [
                Item(
                    iconName: "CurrentData/Tests",
                    title: titleValue(data.testsTotal, withKey: "current_data_item_tests"),
                    subtitle: titleValue(data.testsIncrease, withKey: "current_data_item_yesterday", showPlus: true)
                ),
                Item(
                    iconName: "CurrentData/Covid",
                    title: titleValue(data.confirmedCasesTotal, withKey: "current_data_item_confirmed"),
                    subtitle: titleValue(data.confirmedCasesIncrease, withKey: "current_data_item_yesterday", showPlus: true)
                ),
                Item(
                    iconName: "CurrentData/Active",
                    title: titleValue(data.activeCasesTotal, withKey: "current_data_item_active"),
                    subtitle: titleValue(data.activeCasesIncrease, withKey: "current_data_item_yesterday", showPlus: true)
                ),
                Item(
                    iconName: "CurrentData/Healthy",
                    title: titleValue(data.curedTotal, withKey: "current_data_item_healthy"),
                    subtitle: titleValue(data.curedIncrease, withKey: "current_data_item_yesterday", showPlus: true)
                ),
                Item(
                    iconName: "CurrentData/Death",
                    title: titleValue(data.deceasedTotal, withKey: "current_data_item_deaths"),
                    subtitle: titleValue(data.deceasedIncrease, withKey: "current_data_item_yesterday", showPlus: true)
                ),
                Item(
                    iconName: "CurrentData/Hospital",
                    title: titleValue(data.currentlyHospitalizedTotal, withKey: "current_data_item_hospitalized"),
                    subtitle: titleValue(data.currentlyHospitalizedIncrease, withKey: "current_data_item_yesterday", showPlus: true)
                ),
            ])
        ]
    }

    private func titleValue(_ value: Int, withKey key: String, showPlus: Bool = false) -> String {
        guard let formattedValue = numberFormatter.string(for: value) else { return "" }
        return String(format: Localizable(key), showPlus && value > 0 ? "+" + formattedValue : formattedValue)
    }
}

extension CurrentDataVM {

     struct Section {
         let header: String?
         let selectableItems: Bool
         let items: [Item]
     }

     struct Item {
         let iconName: String
         let title: String
         let subtitle: String?
     }
}
